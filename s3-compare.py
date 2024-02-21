import boto3

def get_s3_permissions(role_name):
    """
    Retrieve S3 permissions for a given IAM role
    """
    iam = boto3.client('iam')
    role_policy = iam.get_role_policy(
        RoleName=role_name,
        PolicyName='AmazonS3FullAccess'  # You can change this to match the policy name you want to check
    )
    statements = role_policy['PolicyDocument']['Statement']
    s3_permissions = []
    for statement in statements:
        if statement['Effect'] == 'Allow' and 's3' in statement['Resource']:
            s3_permissions.append(statement['Action'])
    return s3_permissions

def compare_s3_permissions(role1_name, role2_name):
    """
    Compare S3 permissions between two IAM roles
    """
    role1_permissions = set(get_s3_permissions(role1_name))
    role2_permissions = set(get_s3_permissions(role2_name))
    
    # Check for permissions present in role1 but not in role2
    permissions_only_in_role1 = role1_permissions - role2_permissions
    
    # Check for permissions present in role2 but not in role1
    permissions_only_in_role2 = role2_permissions - role1_permissions
    
    return permissions_only_in_role1, permissions_only_in_role2

if __name__ == "__main__":
    role1_name = 'Role1Name'
    role2_name = 'Role2Name'
    
    permissions_only_in_role1, permissions_only_in_role2 = compare_s3_permissions(role1_name, role2_name)
    
    print(f"Permissions present in {role1_name} but not in {role2_name}:")
    print(permissions_only_in_role1)
    
    print(f"\nPermissions present in {role2_name} but not in {role1_name}:")
    print(permissions_only_in_role2)