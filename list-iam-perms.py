import boto3

def list_permissions(policy_arn):
    iam = boto3.client('iam')

    try:
        response = iam.get_policy(PolicyArn=policy_arn)
        policy_version = response['Policy']['DefaultVersionId']
        policy_document = iam.get_policy_version(PolicyArn=policy_arn, VersionId=policy_version)['PolicyVersion']['Document']

        if 'Statement' in policy_document:
            for statement in policy_document['Statement']:
                print("Effect:", statement['Effect'])
                print("Action:", statement['Action'])
                print("Resource:", statement['Resource'])
                print()
        else:
            print("No statements found in the policy.")

    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    policy_arn = "YOUR_POLICY_ARN_HERE"  # Replace with the ARN of the IAM policy you want to list permissions for
    list_permissions(policy_arn)
