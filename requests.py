import urllib.request
import urllib.error

# Set the URL you want to request
url = "https://www.example.com"

try:
    # Send the request and get the response
    response = urllib.request.urlopen(url)
    
    # Print the response status code
    print(f"HTTP Status Code: {response.getcode()}") # 200 for success

    # Read the response data
    data = response.read()
    print(data.decode('utf-8'))

except urllib.error.HTTPError as e:
    # Print the error code if there's an HTTP error
    print(f"HTTP Error: {e.code}") # e.g. 404 for Not Found

except urllib.error.URLError as e:
    # Print the error reason if there's a URL error
    print(f"URL Error: {e.reason}")
