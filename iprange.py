import urllib.request, json

with urllib.urlopen("https://ip-ranges.amazonaws.com/ip-ranges.json") as url:
    data = json.loads(url.read().decode())
    print(data)