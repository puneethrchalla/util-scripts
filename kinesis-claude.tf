# Account B - Main Infrastructure

# variables.tf

variable “account_a_id” {
description = “Client AWS Account ID (Account A)”
type        = string
}

variable “splunk_hec_endpoint” {
description = “Splunk HEC endpoint URL”
type        = string
}

variable “splunk_hec_token” {
description = “Splunk HEC token”
type        = string
sensitive   = true
}

variable “vpc_id” {
description = “VPC ID for PrivateLink”
type        = string
}

variable “subnet_ids” {
description = “Subnet IDs for VPC endpoint”
type        = list(string)
}

variable “s3_bucket_name” {
description = “S3 bucket name for log archival”
type        = string
}

# main.tf

terraform {
required_providers {
aws = {
source  = “hashicorp/aws”
version = “~> 5.0”
}
}
}

provider “aws” {
region = “us-east-1”
}

# Kinesis Data Stream

resource “aws_kinesis_stream” “logs” {
name             = “centralized-logs-stream”
shard_count      = 2
retention_period = 24

shard_level_metrics = [
“IncomingBytes”,
“IncomingRecords”,
“OutgoingBytes”,
“OutgoingRecords”,
]

stream_mode_details {
stream_mode = “PROVISIONED”
}

tags = {
Environment = “production”
Purpose     = “log-aggregation”
}
}

# Kinesis Stream Policy - Allow Account A to put records

resource “aws_kinesis_stream_policy” “logs_policy” {
stream_name = aws_kinesis_stream.logs.name

policy = jsonencode({
Version = “2012-10-17”
Statement = [
{
Sid    = “AllowAccountAPutRecords”
Effect = “Allow”
Principal = {
AWS = “arn:aws:iam::${var.account_a_id}:root”
}
Action = [
“kinesis:PutRecord”,
“kinesis:PutRecords”
]
Resource = aws_kinesis_stream.logs.arn
}
]
})
}

# S3 Bucket for Log Archive

resource “aws_s3_bucket” “logs_archive” {
bucket = var.s3_bucket_name

tags = {
Purpose = “log-archive”
}
}

resource “aws_s3_bucket_versioning” “logs_archive” {
bucket = aws_s3_bucket.logs_archive.id

versioning_configuration {
status = “Enabled”
}
}

resource “aws_s3_bucket_server_side_encryption_configuration” “logs_archive” {
bucket = aws_s3_bucket.logs_archive.id

rule {
apply_server_side_encryption_by_default {
sse_algorithm = “AES256”
}
}
}

# IAM Role for Firehose

resource “aws_iam_role” “firehose_role” {
name = “kinesis-firehose-logs-role”

assume_role_policy = jsonencode({
Version = “2012-10-17”
Statement = [
{
Action = “sts:AssumeRole”
Effect = “Allow”
Principal = {
Service = “firehose.amazonaws.com”
}
}
]
})
}

resource “aws_iam_role_policy” “firehose_policy” {
name = “kinesis-firehose-logs-policy”
role = aws_iam_role.firehose_role.id

policy = jsonencode({
Version = “2012-10-17”
Statement = [
{
Effect = “Allow”
Action = [
“s3:AbortMultipartUpload”,
“s3:GetBucketLocation”,
“s3:GetObject”,
“s3:ListBucket”,
“s3:ListBucketMultipartUploads”,
“s3:PutObject”
]
Resource = [
aws_s3_bucket.logs_archive.arn,
“${aws_s3_bucket.logs_archive.arn}/*”
]
},
{
Effect = “Allow”
Action = [
“kinesis:DescribeStream”,
“kinesis:GetShardIterator”,
“kinesis:GetRecords”,
“kinesis:ListShards”
]
Resource = aws_kinesis_stream.logs.arn
},
{
Effect = “Allow”
Action = [
“logs:PutLogEvents”
]
Resource = aws_cloudwatch_log_group.firehose_logs.arn
}
]
})
}

# CloudWatch Log Group for Firehose

resource “aws_cloudwatch_log_group” “firehose_logs” {
name              = “/aws/kinesisfirehose/logs-archive”
retention_in_days = 7
}

resource “aws_cloudwatch_log_stream” “firehose_logs” {
name           = “S3Delivery”
log_group_name = aws_cloudwatch_log_group.firehose_logs.name
}

# Kinesis Firehose Delivery Stream

resource “aws_kinesis_firehose_delivery_stream” “logs_to_s3” {
name        = “logs-to-s3”
destination = “extended_s3”

kinesis_source_configuration {
kinesis_stream_arn = aws_kinesis_stream.logs.arn
role_arn           = aws_iam_role.firehose_role.arn
}

extended_s3_configuration {
role_arn   = aws_iam_role.firehose_role.arn
bucket_arn = aws_s3_bucket.logs_archive.arn

```
prefix              = "logs/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
error_output_prefix = "errors/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}/"

buffering_size     = 5
buffering_interval = 300

compression_format = "GZIP"

cloudwatch_logging_options {
  enabled         = true
  log_group_name  = aws_cloudwatch_log_group.firehose_logs.name
  log_stream_name = aws_cloudwatch_log_stream.firehose_logs.name
}
```

}

tags = {
Purpose = “log-archive”
}
}

# Security Group for VPC Endpoint

resource “aws_security_group” “vpc_endpoint_sg” {
name        = “splunk-vpc-endpoint-sg”
description = “Security group for Splunk VPC endpoint”
vpc_id      = var.vpc_id

ingress {
from_port   = 443
to_port     = 443
protocol    = “tcp”
cidr_blocks = [“10.0.0.0/8”]
description = “Allow HTTPS from VPC”
}

egress {
from_port   = 0
to_port     = 0
protocol    = “-1”
cidr_blocks = [“0.0.0.0/0”]
}

tags = {
Name = “splunk-vpc-endpoint-sg”
}
}

# VPC Endpoint for Splunk (PrivateLink)

resource “aws_vpc_endpoint” “splunk” {
vpc_id              = var.vpc_id
service_name        = “com.amazonaws.vpce.us-east-1.vpce-svc-xxxxxxxxxx” # Replace with actual Splunk service name
vpc_endpoint_type   = “Interface”
subnet_ids          = var.subnet_ids
security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
private_dns_enabled = true

tags = {
Name = “splunk-privatelink”
}
}

# IAM Role for Lambda

resource “aws_iam_role” “lambda_role” {
name = “kinesis-to-splunk-lambda-role”

assume_role_policy = jsonencode({
Version = “2012-10-17”
Statement = [
{
Action = “sts:AssumeRole”
Effect = “Allow”
Principal = {
Service = “lambda.amazonaws.com”
}
}
]
})
}

resource “aws_iam_role_policy” “lambda_policy” {
name = “kinesis-to-splunk-lambda-policy”
role = aws_iam_role.lambda_role.id

policy = jsonencode({
Version = “2012-10-17”
Statement = [
{
Effect = “Allow”
Action = [
“kinesis:DescribeStream”,
“kinesis:DescribeStreamSummary”,
“kinesis:GetRecords”,
“kinesis:GetShardIterator”,
“kinesis:ListShards”,
“kinesis:ListStreams”,
“kinesis:SubscribeToShard”
]
Resource = aws_kinesis_stream.logs.arn
},
{
Effect = “Allow”
Action = [
“logs:CreateLogGroup”,
“logs:CreateLogStream”,
“logs:PutLogEvents”
]
Resource = “arn:aws:logs:*:*:*”
},
{
Effect = “Allow”
Action = [
“ec2:CreateNetworkInterface”,
“ec2:DescribeNetworkInterfaces”,
“ec2:DeleteNetworkInterface”,
“ec2:AssignPrivateIpAddresses”,
“ec2:UnassignPrivateIpAddresses”
]
Resource = “*”
}
]
})
}

# CloudWatch Log Group for Lambda

resource “aws_cloudwatch_log_group” “lambda_logs” {
name              = “/aws/lambda/kinesis-to-splunk”
retention_in_days = 7
}

# Lambda Function

resource “aws_lambda_function” “kinesis_to_splunk” {
filename         = “lambda_function.zip”
function_name    = “kinesis-to-splunk”
role            = aws_iam_role.lambda_role.arn
handler         = “lambda_function.lambda_handler”
source_code_hash = filebase64sha256(“lambda_function.zip”)
runtime         = “python3.11”
timeout         = 300
memory_size     = 512

vpc_config {
subnet_ids         = var.subnet_ids
security_group_ids = [aws_security_group.vpc_endpoint_sg.id]
}

environment {
variables = {
SPLUNK_HEC_URL   = var.splunk_hec_endpoint
SPLUNK_HEC_TOKEN = var.splunk_hec_token
}
}

depends_on = [
aws_cloudwatch_log_group.lambda_logs,
aws_iam_role_policy.lambda_policy
]
}

# Event Source Mapping - Kinesis to Lambda

resource “aws_lambda_event_source_mapping” “kinesis_to_lambda” {
event_source_arn  = aws_kinesis_stream.logs.arn
function_name     = aws_lambda_function.kinesis_to_splunk.arn
starting_position = “LATEST”
batch_size        = 100
maximum_batching_window_in_seconds = 10
parallelization_factor = 1

function_response_types = [“ReportBatchItemFailures”]
}

# Outputs

output “kinesis_stream_arn” {
description = “ARN of the Kinesis stream”
value       = aws_kinesis_stream.logs.arn
}

output “kinesis_stream_name” {
description = “Name of the Kinesis stream”
value       = aws_kinesis_stream.logs.name
}

output “firehose_delivery_stream_arn” {
description = “ARN of the Firehose delivery stream”
value       = aws_kinesis_firehose_delivery_stream.logs_to_s3.arn
}

output “s3_bucket_name” {
description = “S3 bucket for log archive”
value       = aws_s3_bucket.logs_archive.id
}

output “lambda_function_arn” {
description = “ARN of the Lambda function”
value       = aws_lambda_function.kinesis_to_splunk.arn
}