# Variables

variable “kinesis_stream_arn” {
description = “ARN of the existing Kinesis stream”
type        = string
}

variable “kinesis_stream_name” {
description = “Name of the existing Kinesis stream”
type        = string
}

variable “private_splunk_hec_url” {
description = “Private Splunk HEC URL (e.g., https://splunk.internal:8088/services/collector)”
type        = string
}

variable “private_splunk_hec_token” {
description = “Splunk HEC token”
type        = string
sensitive   = true
}

variable “vpc_id” {
description = “VPC ID where private Splunk is accessible”
type        = string
}

variable “subnet_ids” {
description = “Subnet IDs for Lambda (should have access to private Splunk)”
type        = list(string)
}

variable “environment” {
description = “Environment name”
type        = string
default     = “production”
}

# Security Group for Lambda

resource “aws_security_group” “lambda_to_splunk” {
name        = “lambda-to-private-splunk-${var.environment}”
description = “Allow Lambda to communicate with private Splunk”
vpc_id      = var.vpc_id

egress {
from_port   = 8088
to_port     = 8088
protocol    = “tcp”
cidr_blocks = [“0.0.0.0/0”]
description = “Splunk HEC”
}

egress {
from_port   = 443
to_port     = 443
protocol    = “tcp”
cidr_blocks = [“0.0.0.0/0”]
description = “HTTPS”
}

tags = {
Name        = “lambda-to-private-splunk-${var.environment}”
Environment = var.environment
}
}

# IAM Role for Lambda

resource “aws_iam_role” “lambda_kinesis_to_splunk” {
name = “lambda-kinesis-to-private-splunk-${var.environment}”

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

tags = {
Environment = var.environment
}
}

# IAM Policy for Lambda

resource “aws_iam_role_policy” “lambda_kinesis_to_splunk” {
name = “lambda-kinesis-to-splunk-policy”
role = aws_iam_role.lambda_kinesis_to_splunk.id

policy = jsonencode({
Version = “2012-10-17”
Statement = [
{
Effect = “Allow”
Action = [
“kinesis:GetRecords”,
“kinesis:GetShardIterator”,
“kinesis:DescribeStream”,
“kinesis:ListStreams”,
“kinesis:ListShards”
]
Resource = var.kinesis_stream_arn
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

# Secrets Manager for Splunk HEC Token

resource “aws_secretsmanager_secret” “splunk_hec_token” {
name        = “private-splunk-hec-token-${var.environment}”
description = “HEC token for private Splunk instance”

tags = {
Environment = var.environment
}
}

resource “aws_secretsmanager_secret_version” “splunk_hec_token” {
secret_id     = aws_secretsmanager_secret.splunk_hec_token.id
secret_string = var.private_splunk_hec_token
}

# IAM Policy for Secrets Manager

resource “aws_iam_role_policy” “lambda_secrets_access” {
name = “lambda-secrets-access”
role = aws_iam_role.lambda_kinesis_to_splunk.id

policy = jsonencode({
Version = “2012-10-17”
Statement = [
{
Effect = “Allow”
Action = [
“secretsmanager:GetSecretValue”
]
Resource = aws_secretsmanager_secret.splunk_hec_token.arn
}
]
})
}

# Lambda Function

resource “aws_lambda_function” “kinesis_to_private_splunk” {
filename         = “lambda_function.zip”
function_name    = “kinesis-to-private-splunk-${var.environment}”
role            = aws_iam_role.lambda_kinesis_to_splunk.arn
handler         = “lambda_function.lambda_handler”
source_code_hash = filebase64sha256(“lambda_function.zip”)
runtime         = “python3.11”
timeout         = 300
memory_size     = 512

vpc_config {
subnet_ids         = var.subnet_ids
security_group_ids = [aws_security_group.lambda_to_splunk.id]
}

environment {
variables = {
SPLUNK_HEC_URL          = var.private_splunk_hec_url
SPLUNK_HEC_TOKEN_SECRET = aws_secretsmanager_secret.splunk_hec_token.name
BATCH_SIZE              = “100”
MAX_RETRIES             = “3”
}
}

tags = {
Environment = var.environment
}
}

# CloudWatch Log Group

resource “aws_cloudwatch_log_group” “lambda_logs” {
name              = “/aws/lambda/${aws_lambda_function.kinesis_to_private_splunk.function_name}”
retention_in_days = 14

tags = {
Environment = var.environment
}
}

# Event Source Mapping

resource “aws_lambda_event_source_mapping” “kinesis_to_lambda” {
event_source_arn  = var.kinesis_stream_arn
function_name     = aws_lambda_function.kinesis_to_private_splunk.arn
starting_position = “LATEST”
batch_size        = 100
parallelization_factor = 1

# Enable error handling

maximum_retry_attempts = 3
maximum_record_age_in_seconds = 604800  # 7 days

# Bisect batch on error

bisect_batch_on_function_error = true

# Destination for failed records (optional)

# destination_config {

# on_failure {

# destination_arn = aws_sqs_queue.dlq.arn

# }

# }

depends_on = [
aws_iam_role_policy.lambda_kinesis_to_splunk
]
}

# CloudWatch Alarms

resource “aws_cloudwatch_metric_alarm” “lambda_errors” {
alarm_name          = “lambda-kinesis-to-splunk-errors-${var.environment}”
comparison_operator = “GreaterThanThreshold”
evaluation_periods  = “2”
metric_name         = “Errors”
namespace           = “AWS/Lambda”
period              = “300”
statistic           = “Sum”
threshold           = “10”
alarm_description   = “This metric monitors lambda errors”
treat_missing_data  = “notBreaching”

dimensions = {
FunctionName = aws_lambda_function.kinesis_to_private_splunk.function_name
}

tags = {
Environment = var.environment
}
}

resource “aws_cloudwatch_metric_alarm” “lambda_throttles” {
alarm_name          = “lambda-kinesis-to-splunk-throttles-${var.environment}”
comparison_operator = “GreaterThanThreshold”
evaluation_periods  = “1”
metric_name         = “Throttles”
namespace           = “AWS/Lambda”
period              = “300”
statistic           = “Sum”
threshold           = “5”
alarm_description   = “This metric monitors lambda throttles”
treat_missing_data  = “notBreaching”

dimensions = {
FunctionName = aws_lambda_function.kinesis_to_private_splunk.function_name
}

tags = {
Environment = var.environment
}
}

# Outputs

output “lambda_function_arn” {
description = “ARN of the Lambda function”
value       = aws_lambda_function.kinesis_to_private_splunk.arn
}

output “lambda_function_name” {
description = “Name of the Lambda function”
value       = aws_lambda_function.kinesis_to_private_splunk.function_name
}

output “lambda_security_group_id” {
description = “Security group ID for Lambda”
value       = aws_security_group.lambda_to_splunk.id
}