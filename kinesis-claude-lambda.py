import json
import gzip
import base64
import os
import urllib3
from datetime import datetime

# Initialize HTTP client

http = urllib3.PoolManager()

# Get environment variables

SPLUNK_HEC_URL = os.environ[‘SPLUNK_HEC_URL’]
SPLUNK_HEC_TOKEN = os.environ[‘SPLUNK_HEC_TOKEN’]

def lambda_handler(event, context):
“””
Process records from Kinesis and send to Splunk HEC

```
Args:
    event: Kinesis event containing records
    context: Lambda context
    
Returns:
    Response with batch item failures for retry
"""
print(f"Processing {len(event['Records'])} records from Kinesis")

batch_item_failures = []
successful_records = 0
failed_records = 0

for record in event['Records']:
    try:
        # Extract Kinesis data
        sequence_number = record['kinesis']['sequenceNumber']
        partition_key = record['kinesis']['partitionKey']
        data = record['kinesis']['data']
        
        # Decode base64 data
        decoded_data = base64.b64decode(data)
        
        # Decompress if gzipped (CloudWatch Logs sends gzipped data)
        try:
            decompressed_data = gzip.decompress(decoded_data)
            log_data = json.loads(decompressed_data.decode('utf-8'))
        except (OSError, gzip.BadGzipFile):
            # Not gzipped, treat as plain text
            log_data = decoded_data.decode('utf-8')
        
        # Process log data
        events = process_log_data(log_data)
        
        # Send to Splunk
        if events:
            send_to_splunk(events)
            successful_records += 1
            print(f"Successfully processed record: {sequence_number}")
        else:
            print(f"No events to send for record: {sequence_number}")
            successful_records += 1
            
    except Exception as e:
        print(f"Error processing record {sequence_number}: {str(e)}")
        failed_records += 1
        # Add to batch item failures for retry
        batch_item_failures.append({
            "itemIdentifier": sequence_number
        })

print(f"Processing complete. Successful: {successful_records}, Failed: {failed_records}")

# Return batch item failures for partial batch response
return {
    "batchItemFailures": batch_item_failures
}
```

def process_log_data(log_data):
“””
Process log data and convert to Splunk HEC format

```
Args:
    log_data: Raw log data (dict or string)
    
Returns:
    List of events in Splunk HEC format
"""
events = []

# Handle CloudWatch Logs format
if isinstance(log_data, dict) and 'logEvents' in log_data:
    log_group = log_data.get('logGroup', 'unknown')
    log_stream = log_data.get('logStream', 'unknown')
    
    for log_event in log_data['logEvents']:
        event = {
            "time": log_event['timestamp'] / 1000,  # Convert to seconds
            "source": log_stream,
            "sourcetype": "aws:cloudwatch",
            "event": {
                "message": log_event['message'],
                "logGroup": log_group,
                "logStream": log_stream,
                "id": log_event.get('id', '')
            }
        }
        
        # Try to parse JSON messages
        try:
            parsed_message = json.loads(log_event['message'])
            event['event']['parsed'] = parsed_message
        except (json.JSONDecodeError, TypeError):
            pass
        
        events.append(event)

# Handle generic JSON format
elif isinstance(log_data, dict):
    event = {
        "time": datetime.utcnow().timestamp(),
        "sourcetype": "_json",
        "event": log_data
    }
    events.append(event)

# Handle plain text
elif isinstance(log_data, str):
    event = {
        "time": datetime.utcnow().timestamp(),
        "sourcetype": "text",
        "event": log_data
    }
    events.append(event)

return events
```

def send_to_splunk(events, max_retries=3):
“””
Send events to Splunk HEC endpoint

```
Args:
    events: List of events in Splunk HEC format
    max_retries: Maximum number of retry attempts
    
Raises:
    Exception: If all retry attempts fail
"""
headers = {
    'Authorization': f'Splunk {SPLUNK_HEC_TOKEN}',
    'Content-Type': 'application/json'
}

# Prepare payload - send events in batch
payload = ""
for event in events:
    payload += json.dumps(event) + "\n"

# Remove trailing newline
payload = payload.rstrip()

for attempt in range(max_retries):
    try:
        response = http.request(
            'POST',
            SPLUNK_HEC_URL,
            body=payload.encode('utf-8'),
            headers=headers,
            timeout=30.0,
            retries=False
        )
        
        if response.status == 200:
            response_data = json.loads(response.data.decode('utf-8'))
            print(f"Successfully sent {len(events)} events to Splunk")
            return
        else:
            error_message = response.data.decode('utf-8')
            print(f"Splunk HEC returned status {response.status}: {error_message}")
            
            # Don't retry on client errors (4xx)
            if 400 <= response.status < 500:
                raise Exception(f"Client error from Splunk: {response.status} - {error_message}")
            
            # Retry on server errors (5xx)
            if attempt < max_retries - 1:
                print(f"Retrying... (attempt {attempt + 2}/{max_retries})")
                continue
            else:
                raise Exception(f"Failed to send to Splunk after {max_retries} attempts")
                
    except urllib3.exceptions.HTTPError as e:
        print(f"HTTP error occurred: {str(e)}")
        if attempt < max_retries - 1:
            print(f"Retrying... (attempt {attempt + 2}/{max_retries})")
            continue
        else:
            raise Exception(f"Failed to send to Splunk after {max_retries} attempts: {str(e)}")
    
    except Exception as e:
        print(f"Error sending to Splunk: {str(e)}")
        if attempt < max_retries - 1:
            print(f"Retrying... (attempt {attempt + 2}/{max_retries})")
            continue
        else:
            raise
```

def validate_environment():
“””
Validate required environment variables are set

```
Raises:
    ValueError: If required environment variables are missing
"""
if not SPLUNK_HEC_URL:
    raise ValueError("SPLUNK_HEC_URL environment variable is not set")

if not SPLUNK_HEC_TOKEN:
    raise ValueError("SPLUNK_HEC_TOKEN environment variable is not set")

print(f"Environment validated. HEC URL: {SPLUNK_HEC_URL}")
```

# Validate environment on cold start

validate_environment()