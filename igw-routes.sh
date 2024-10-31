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

# Fetch all route tables in the VPC
ROUTE_TABLES=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query 'RouteTables[*].{ID:RouteTableId}' --output text)

echo "Fetching public subnets in VPC: $VPC_ID"

# Initialize an empty array to store public subnets
PUBLIC_SUBNETS=()

# Loop through each route table and check for a route to an internet gateway
for RTB in $ROUTE_TABLES
do
    # Check if the route table has a route to an internet gateway
    ROUTE_EXISTS=$(aws ec2 describe-route-tables --route-table-ids $RTB --query 'RouteTables[0].Routes[?GatewayId!=`null` && contains(GatewayId, `igw-`)] | length(@)' --output text)
    
    if [ "$ROUTE_EXISTS" -gt 0 ]
    then
        # If a route to an internet gateway exists, fetch the associated subnets
        SUBNETS=$(aws ec2 describe-route-tables --route-table-ids $RTB --query 'RouteTables[0].Associations[?SubnetId!=`null`].SubnetId' --output text)
        PUBLIC_SUBNETS+=($SUBNETS)
    fi
done

# Output the list of public subnets
if [ ${#PUBLIC_SUBNETS[@]} -eq 0 ]
then
    echo "No public subnets found in VPC: $VPC_ID"
else
    echo "Public subnets in VPC: $VPC_ID"
    for SUBNET in "${PUBLIC_SUBNETS[@]}"
    do
        echo $SUBNET
    done
fi