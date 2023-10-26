import boto3

# Initialize the Boto3 EC2 client
ec2_client = boto3.client('ec2')

# Replace 'vpce-xxxxxx' with the ID of your VPC endpoint
vpc_endpoint_id = 'vpce-xxxxxx'

# Define the new VPC endpoint policy
new_policy = {
    'Statement': [
        {
            'Action': 'ec2:Describe*',
            'Effect': 'Allow',
            'Resource': '*'
        }
    ]
}

# Modify the VPC endpoint policy
response = ec2_client.modify_vpc_endpoint_policy(
    ServiceId=vpc_endpoint_id,
    PolicyDocument=new_policy
)

print(f"VPC endpoint policy modified: {response}")