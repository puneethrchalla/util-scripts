import boto3

# Create a Route53 client
route53 = boto3.client('route53')

# Specify the hosted zone ID
hosted_zone_id = 'Z1D633PQ1QVFVP'  # Replace with your hosted zone ID

# Initialize variables for pagination
next_record_name = ''
next_record_type = ''
is_truncated = True

while is_truncated:
    # List resource record sets
    response = route53.list_resource_record_sets(
        HostedZoneId=hosted_zone_id,
        StartRecordName=next_record_name,
        StartRecordType=next_record_type
    )

    # Print the record sets
    for record in response['ResourceRecordSets']:
        print(record)

    # Update pagination variables
    next_record_name = response.get('NextRecordName', '')
    next_record_type = response.get('NextRecordType', '')
    is_truncated = response['IsTruncated']