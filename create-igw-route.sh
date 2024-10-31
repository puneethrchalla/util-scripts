#!/bin/bash

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null
then
    echo "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if the VPC ID is provided as an argument
if [ -z "$1" ]
then
    echo "Usage: $0 <VPC-ID>"
    exit 1
fi

VPC_ID=$1

# Fetch the Internet Gateway ID associated with the VPC
INTERNET_GATEWAY_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways[0].InternetGatewayId' --output text)

# Check if the Internet Gateway ID was found
if [ "$INTERNET_GATEWAY_ID" == "None" ]
then
    echo "No Internet Gateway found for VPC: $VPC_ID. Please create and attach an Internet Gateway before running this script."
    exit 1
fi

echo "Found Internet Gateway: $INTERNET_GATEWAY_ID for VPC: $VPC_ID"
echo "Adding internet route to all route tables for public subnets in VPC: $VPC_ID"

# Fetch all route tables in the VPC
ROUTE_TABLES=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query 'RouteTables[*].{ID:RouteTableId}' --output text)

# Loop through each route table and add a route to the internet gateway
for RTB in $ROUTE_TABLES
do
    # Check if the route table has a route to an internet gateway
    ROUTE_EXISTS=$(aws ec2 describe-route-tables --route-table-ids $RTB --query 'RouteTables[0].Routes[?GatewayId!=`null` && contains(GatewayId, `igw-`)] | length(@)' --output text)
    
    if [ "$ROUTE_EXISTS" -eq 0 ]
    then
        # Add a route to the internet gateway for the destination CIDR 0.0.0.0/0
        echo "Adding internet route to route table: $RTB"
        aws ec2 create-route --route-table-id $RTB --destination-cidr-block 0.0.0.0/0 --gateway-id $INTERNET_GATEWAY_ID
    else
        echo "Route table $RTB already has an internet route. Skipping."
    fi
done

echo "Internet routes have been added to the route tables in VPC: $VPC_ID"