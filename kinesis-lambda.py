import base64
import gzip
import json
import os
import time
import uuid
from typing import List, Dict, Any

import boto3
from botocore.config import Config
import urllib3

# Reuse connections
_http = urllib3.PoolManager(cert_reqs="CERT_REQUIRED")
_sm   = boto3.client("secretsmanager", config=Config(retries={"max_attempts": 5, "mode": "standard"}))

HEC_URL   = os.environ.get("SPLUNK_HEC_URL")  # e.g., https://http-inputs.<stack>.splunkcloud.com:8088
VERIFY_TLS = os.environ.get("VERIFY_TLS", "true").lower() == "true"
CA_BUNDLE_PATH = os.environ.get("CA_BUNDLE_PATH", "").strip()

SPLUNK_INDEX      = os.environ.get("SPLUNK_INDEX", "main")
SPLUNK_SOURCETYPE = os.environ.get("SPLUNK_SOURCETYPE", "aws:cloudwatchlogs")
SPLUNK_SOURCE     = os.environ.get("SPLUNK_SOURCE", "cloudwatch")

TOKEN_SECRET_ARN = os.environ["SPLUNK_HEC_TOKEN_SECRET_ARN"]
HEC_TOKEN = _sm.get_secret_value(SecretId=TOKEN_SECRET_ARN)["SecretString"]

if CA_BUNDLE_PATH:
    # If you supply a custom CA bundle, create a separate HTTP manager that uses it.
    _http = urllib3.PoolManager(
        cert_reqs="CERT_REQUIRED",
        ca_certs=CA_BUNDLE_PATH,
    )

def _decode_record(b64_gz_payload: str) -> Dict[str, Any]:
    raw = base64.b64decode(b64_gz_payload)
    data = gzip.decompress(raw)
    return json.loads(data)

def _to_splunk_events(record: Dict[str, Any]) -> List[Dict[str, Any]]:
    if record.get("messageType") != "DATA_MESSAGE":
        return []
    owner = record.get("owner")
    log_group = record.get("logGroup")
    log_stream = record.get("logStream")
    common = {
        "source": SPLUNK_SOURCE or log_group,
        "sourcetype": SPLUNK_SOURCETYPE,
        "index": SPLUNK_INDEX,
        # You can set "host" here if your tenancy model needs it.
    }
    out = []
    for e in record.get("logEvents", []):
        evt = {
            **common,
            "time": e.get("timestamp", int(time.time() * 1000)) / 1000.0,
            "event": {
                "message": e.get("message", ""),
                "owner": owner,
                "logGroup": log_group,
                "logStream": log_stream,
            },
        }
        # If message looks like JSON, optionally parse and replace/augment:
        msg = e.get("message", "").strip()
        if msg.startswith("{") and msg.endswith("}"):
            try:
                j = json.loads(msg)
                evt["event"] = {**evt["event"], **j}
            except Exception:
                pass
        out.append(evt)
    return out

def _post_hec(events: List[Dict[str, Any]]) -> None:
    """
    Sends events to Splunk HEC /services/collector/event
    Payload: one JSON per line (newline-delimited)
    Retries on 5xx with exponential backoff. For 4xx, raises.
    """
    if not events:
        return

    body_lines = []
    for evt in events:
        body_lines.append(json.dumps(evt, separators=(",", ":")))
    body = "\n".join(body_lines).encode("utf-8")

    headers = {
        "Authorization": f"Splunk {HEC_TOKEN}",
        "Content-Type": "application/json",
        # Helps with at-least-once idempotency
        "X-Splunk-Request-Channel": str(uuid.uuid4()),
    }

    backoff = 0.5
    for attempt in range(6):
        r = _http.request(
            "POST",
            f"{HEC_URL}/services/collector/event",
            headers=headers,
            body=body,
            timeout=urllib3.Timeout(connect=5.0, read=10.0),
            preload_content=True,
            retries=False,  # we do our own
        )
        status = r.status
        data = r.data[:512]
        if status in (200, 201):
            return
        if 500 <= status < 600:
            time.sleep(backoff)
            backoff = min(backoff * 2.0, 8.0)
            continue
        # 4xx is caller error; raise with small payload for CWL
        raise RuntimeError(f"HEC {status}: {data!r}")
    raise RuntimeError("HEC retries exhausted")

def handler(event, context):
    # event["Records"] → list of Kinesis records
    batch: List[Dict[str, Any]] = []
    for rec in event.get("Records", []):
        payload = rec["kinesis"]["data"]
        decoded = _decode_record(payload)
        batch.extend(_to_splunk_events(decoded))

    # Split large batches to avoid 413s. ~1-2k events per POST is safe; tune as needed.
    MAX = 2000
    for i in range(0, len(batch), MAX):
        _post_hec(batch[i : i + MAX])

    return {"ok": True, "events": len(batch)}