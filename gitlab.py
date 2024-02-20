import requests

def trigger_pipeline(project_id, token, ref, variables):
    url = f"https://gitlab.com/api/v4/projects/{project_id}/trigger/pipeline"
    headers = {
        "PRIVATE-TOKEN": token
    }
    data = {
        "ref": ref,
        "variables[ENV_VAR_1]": variables["ENV_VAR_1"],
        "variables[ENV_VAR_2]": variables["ENV_VAR_2"],
        # Add more variables as needed
    }
    response = requests.post(url, headers=headers, data=data)
    if response.status_code == 200:
        print("Pipeline triggered successfully.")
    else:
        print("Failed to trigger pipeline. Status code:", response.status_code)

if __name__ == "__main__":
    project_id = "YOUR_PROJECT_ID"
    token = "YOUR_PRIVATE_TOKEN"
    ref = "master"  # Specify the branch or tag you want to trigger the pipeline for
    variables = {
        "ENV_VAR_1": "value1",
        "ENV_VAR_2": "value2",
        # Add more variables as needed
    }
    trigger_pipeline(project_id, token, ref, variables)