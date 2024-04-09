import boto3

# Create an ELBv2 client
elb_client = boto3.client('elbv2')

# Get all NLBs with name suffix 'klb'
nlbs = elb_client.describe_load_balancers(
    Names=[
        {'Prefix': 'klb'}
    ]
)['LoadBalancers']

for nlb in nlbs:
    nlb_name = nlb['LoadBalancerName']
    print(f"\nLoad Balancer: {nlb_name}")

    # Get target groups for this NLB
    target_groups = elb_client.describe_target_groups(
        LoadBalancerArn=nlb['LoadBalancerArn']
    )['TargetGroups']

    for tg in target_groups:
        tg_name = tg['TargetGroupName']
        print(f"  Target Group: {tg_name}")

        # Get health of targets in this target group
        target_health = elb_client.describe_target_health(
            TargetGroupArn=tg['TargetGroupArn']
        )['TargetHealthDescriptions']

        for target in target_health:
            target_id = target['Target']['Id']
            target_state = target['TargetHealth']['State']
            print(f"    Target: {target_id} - State: {target_state}")
