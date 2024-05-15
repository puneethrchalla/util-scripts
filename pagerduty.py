import requests

# Replace these variables with your actual data
API_TOKEN = 'YOUR_PAGERDUTY_API_TOKEN'
USER_ID = 'PAGERDUTY_USER_ID'
HEADERS = {
    'Authorization': f'Token token={API_TOKEN}',
    'Content-Type': 'application/json'
}

def get_incidents(user_id):
    url = 'https://api.pagerduty.com/incidents'
    params = {
        'user_ids[]': user_id,
        'statuses[]': 'triggered,acknowledged'
    }
    response = requests.get(url, headers=HEADERS, params=params)
    response.raise_for_status()  # Will raise an HTTPError if the HTTP request returned an unsuccessful status code
    return response.json()['incidents']

def resolve_incident(incident_id):
    url = f'https://api.pagerduty.com/incidents/{incident_id}'
    payload = {
        'incident': {
            'type': 'incident_reference',
            'status': 'resolved'
        }
    }
    response = requests.put(url, headers=HEADERS, json=payload)
    response.raise_for_status()  # Will raise an HTTPError if the HTTP request returned an unsuccessful status code

def main():
    incidents = get_incidents(USER_ID)
    for incident in incidents:
        incident_id = incident['id']
        print(f"Resolving incident {incident_id}")
        resolve_incident(incident_id)
        print(f"Resolved incident {incident_id}")

if __name__ == '__main__':
    main()