import csv
import ssl
import socket

def get_ssl_issuer(fqdn, port=443):
    try:
        ctx = ssl.create_default_context()
        with ctx.wrap_socket(socket.socket(), server_hostname=fqdn) as s:
            s.settimeout(5)
            s.connect((fqdn, port))
            cert = s.getpeercert()
            issuer = dict(x[0] for x in cert['issuer'])
            return issuer.get('organizationName', '')
    except Exception as e:
        return f"Error: {e}"

def process_csv(file_path):
    fqdn_list = []

    with open(file_path, newline='', encoding='utf-8') as csvfile:
        reader = csv.DictReader(csvfile)
        for row in reader:
            if "Application - PROD" in row.get("Deployment Name", ""):
                fqdn = row.get("Certificate Name", "").strip()
                if fqdn:
                    fqdn_list.append(fqdn)

    for fqdn in fqdn_list:
        issuer = get_ssl_issuer(fqdn)
        if "G1" in issuer:
            print(f"{fqdn} => Issuer: {issuer} (G1 Found)")
        else:
            print(f"{fqdn} => Issuer: {issuer}")

# Example usage
process_csv('your_file.csv')