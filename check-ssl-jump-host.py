#!/usr/bin/env python3

import json
import csv
import ssl
import socket
import sys
import os

def get_ssl_cert_info(fqdn, port=443):
    try:
        ctx = ssl.create_default_context()
        with ctx.wrap_socket(socket.socket(), server_hostname=fqdn) as s:
            s.settimeout(5)
            s.connect((fqdn, port))
            cert = s.getpeercert()

            issuer = dict(x[0] for x in cert['issuer']).get('organizationName', '')
            subject = dict(x[0] for x in cert['subject'])
            common_name = subject.get('commonName', '')

            return issuer, common_name
    except Exception as e:
        return f"Error: {e}", ""

def main(json_path, output_csv):
    if not os.path.isfile(json_path):
        print(f"Error: File '{json_path}' does not exist.")
        sys.exit(1)

    with open(json_path, 'r', encoding='utf-8') as f:
        fqdns = json.load(f)

    with open(output_csv, 'w', newline='', encoding='utf-8') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(["FQDN", "Issuer", "Common Name"])

        for fqdn in fqdns:
            issuer, common_name = get_ssl_cert_info(fqdn)
            writer.writerow([fqdn, issuer, common_name])
            print(f"{fqdn} => Issuer: {issuer}, CN: {common_name}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 ssl_issuer_to_csv.py fqdns.json output.csv")
        sys.exit(1)

    json_path = sys.argv[1]
    output_csv = sys.argv[2]
    main(json_path, output_csv)