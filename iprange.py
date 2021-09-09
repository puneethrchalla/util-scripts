#!/usr/bin/env python3

import urllib.request, json
import os
import boto3

try:
    # Clients
    ec2 = boto3.client('ec2')

    # sanitizing inputs
    services = os.environ["SERVICES"].strip().split(",")
    regions  = os.environ["SERVICE_REGIONS"].strip().split(",")
    golden_sg = os.environ["GOLDEN_SG"]
    port = os.environ["GOLDEN_SG_PORT"]

    # # fetch previous list from S3
    # s3_raw = open('./iprange.json')
    # s3_data = json.load(s3_raw)
    # s3_raw.close()

    # fetch IPs from SG
    response =  ec2.describe_security_groups()
    sg_ips = []

    for sg in response['SecurityGroups']:
        if sg['GroupName'] == golden_sg:
            for rules in sg['IpPermissionsEgress']:
                if rules['FromPort'] == int(port):
                    for ip in rules['IpRanges']:
                        sg_ips.append(ip['CidrIp'])

    # fetch new list from AWS website
    aws_raw = urllib.request.urlopen("https://ip-ranges.amazonaws.com/ip-ranges.json")
    aws_data = json.loads(aws_raw.read().decode())

    def ip_diff(list_key, value_key):
        for ip in aws_data[list_key]:
            if ip["region"] in regions and ip["service"] in services and ip[value_key] not in sg_ips:
                print("{} ({} in {})".format(ip[value_key],ip["service"],ip["region"]))

    # compare lists & extract new IPs
    print("::::::::::: IPv4 :::::::::::")
    ip_diff("prefixes", "ip_prefix")
except Exception as e:
    print(e)
# print("::::::::::: IPv6 :::::::::::")
# ip_diff("ipv6_prefixes", "ipv6_prefix")