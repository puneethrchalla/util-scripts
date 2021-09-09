#!/usr/bin/env python3

import urllib.request, json
import os

# sanitizing inputs
services = os.environ["SERVICES"].strip().split(",")
regions  = os.environ["SERVICE_REGIONS"].strip().split(",")

# fetch previous list from S3
s3_raw = open('./iprange.json')
s3_data = json.load(s3_raw)
s3_raw.close()

# fetch new list from AWS website
aws_raw = urllib.request.urlopen("https://ip-ranges.amazonaws.com/ip-ranges.json")
aws_data = json.loads(aws_raw.read().decode())

def ip_diff(list_key, value_key):
    for ip in aws_data[list_key]:
        if ip not in s3_data[list_key] and ip["region"] in regions and ip["service"] in services:
            print("{} ({} in {})".format(ip[value_key],ip["service"],ip["region"]))

# compare lists & extract new IPs
print("::::::::::: IPv4 :::::::::::")
ip_diff("prefixes", "ip_prefix")
print("::::::::::: IPv6 :::::::::::")
ip_diff("ipv6_prefixes", "ipv6_prefix")