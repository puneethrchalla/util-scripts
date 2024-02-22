import boto3

def get_task_role(cluster_name, service_name):
    ecs = boto3.client('ecs')

    try:
        response = ecs.describe_services(
            cluster=cluster_name,
            services=[service_name]
        )
        if 'services' in response and len(response['services']) > 0:
            task_definition = response['services'][0]['taskDefinition']
            task_definition_response = ecs.describe_task_definition(
                taskDefinition=task_definition
            )
            task_role_arn = task_definition_response['taskDefinition']['taskRoleArn']
            return task_role_arn
        else:
            print(f"No service found with name '{service_name}' in cluster '{cluster_name}'.")
            return None
    except Exception as e:
        print(f"Error: {e}")
        return None

if __name__ == "__main__":
    cluster_name = "YOUR_CLUSTER_NAME"
    service_name = "YOUR_SERVICE_NAME"

    task_role_arn = get_task_role(cluster_name, service_name)
    if task_role_arn:
        print(f"Task Role ARN for service '{service_name}' in cluster '{cluster_name}': {task_role_arn}")
