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
    
import urllib.request
import socket

# Set the URL you want to request
url = "https://www.example.com"

# Set the timeout value in seconds
timeout = 5

# Create a request object
req = urllib.request.Request(url)

# Create a response object
try:
    # Set the default timeout for sockets
    socket.setdefaulttimeout(timeout)
    
    # Send the request and get the response
    response = urllib.request.urlopen(req)
    
    # Read the response data
    data = response.read()
    
    # Print the response data
    print(data.decode('utf-8'))

except socket.timeout:
    print(f"Request timed out after {timeout} seconds.")
except urllib.error.URLError as e:
    print(f"Error: {e.reason}")