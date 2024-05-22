import requests

def make_get_request(url):
    try:
        response = requests.get(url)
        response.raise_for_status()  # Check if the request was successful
        print(f"Response Status Code: {response.status_code}")
        print(f"Response Headers: {response.headers}")
        print(f"Response Content: {response.text}")
    except requests.exceptions.HTTPError as http_err:
        print(f"HTTP error occurred: {http_err}")
    except Exception as err:
        print(f"An error occurred: {err}")

if __name__ == "__main__":
    url = "https://api.github.com"  # Example URL
    make_get_request(url)