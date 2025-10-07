terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.50"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.1"
    }
  }
}

provider "aws" {
  region = var.region
}

locals {
  name_prefix = "splunk-log-pipeline"
  tags        = merge(var.tags, { "app" = "kinesis-to-splunk" })
}

# --------------------------
# KMS for Kinesis (optional)
# --------------------------
resource "aws_kms_key" "kinesis" {
  description             = "KMS key for Kinesis stream encryption"
  deletion_window_in_days = 7
  tags                    = local.tags
}

# --------------------------
# Kinesis Data Stream
# --------------------------
resource "aws_kinesis_stream" "cwlogs" {
  name = var.kinesis_stream_name

  stream_mode_details { stream_mode = "ON_DEMAND" }
  encryption_type = "KMS"
  kms_key_id     = aws_kms_key.kinesis.arn

  tags = local.tags
}

# ------------------------------------------------
# IAM role assumed by CloudWatch Logs (your acct)
# ------------------------------------------------
data "aws_iam_policy_document" "logs_assume" {
  statement {
    effect = "Allow"
    principals { type = "Service" identifiers = ["logs.${var.region}.amazonaws.com"] }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "logs_delivery" {
  name               = "${local.name_prefix}-cwlogs-delivery"
  assume_role_policy = data.aws_iam_policy_document.logs_assume.json
  tags               = local.tags
}

data "aws_iam_policy_document" "logs_to_kinesis" {
  statement {
    effect    = "Allow"
    actions   = ["kinesis:PutRecord", "kinesis:PutRecords", "kinesis:DescribeStream"]
    resources = [aws_kinesis_stream.cwlogs.arn]
  }
}

resource "aws_iam_role_policy" "logs_delivery" {
  name   = "${local.name_prefix}-cwlogs-to-kinesis"
  role   = aws_iam_role.logs_delivery.id
  policy = data.aws_iam_policy_document.logs_to_kinesis.json
}

# ------------------------------------------------
# CloudWatch Logs Destination (in your account)
# ------------------------------------------------
resource "aws_cloudwatch_log_destination" "from_client" {
  name       = "${local.name_prefix}-from-client"
  role_arn   = aws_iam_role.logs_delivery.arn
  target_arn = aws_kinesis_stream.cwlogs.arn
}

# Allow the client account to PUT to this destination
data "aws_iam_policy_document" "destination_access" {
  statement {
    effect = "Allow"
    principals { type = "AWS" identifiers = [var.client_account_id] }
    actions   = ["logs:PutSubscriptionFilter", "logs:DeleteSubscriptionFilter", "logs:DescribeSubscriptionFilters", "logs:PutDestination", "logs:PutDestinationPolicy", "logs:PutLogEvents", "logs:CreateLogStream"]
    resources = [aws_cloudwatch_log_destination.from_client.arn]
  }
}

resource "aws_cloudwatch_log_destination_policy" "from_client" {
  destination_name = aws_cloudwatch_log_destination.from_client.name
  access_policy    = data.aws_iam_policy_document.destination_access.json
}

# --------------------------
# VPC Endpoint (PrivateLink)
# --------------------------
resource "aws_security_group" "vpce_splunk" {
  name        = "${local.name_prefix}-vpce-splunk"
  description = "Allow HTTPS egress to Splunk HEC over PrivateLink"
  vpc_id      = var.vpc_id
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # or restrict to Splunk ENI CIDRs if known
  }
  tags = local.tags
}

resource "aws_vpc_endpoint" "splunk_hec" {
  vpc_id              = var.vpc_id
  service_name        = var.splunk_hec_service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpce_splunk.id]
  private_dns_enabled = var.splunk_private_dns_enabled
  tags                = local.tags
}

# --------------------------
# Optional Route53 override when private DNS is disabled
# --------------------------
resource "aws_route53_zone" "hec_private" {
  count = var.splunk_private_dns_enabled ? 0 : 1
  name  = var.splunk_hec_hostname != null ? var.splunk_hec_hostname : "hec.local"
  vpc { vpc_id = var.vpc_id }
  tags = local.tags
}

# Alias record from hostname → VPCE DNS
# The service exposes multiple DNS names; we point exact hostname your code calls to the first DNS entry.
resource "aws_route53_record" "hec_alias" {
  count   = var.splunk_private_dns_enabled ? 0 : 1
  zone_id = aws_route53_zone.hec_private[0].zone_id
  name    = var.splunk_hec_hostname
  type    = "A"
  alias {
    name                   = aws_vpc_endpoint.splunk_hec.dns_entry[0].dns_name
    zone_id                = aws_vpc_endpoint.splunk_hec.dns_entry[0].hosted_zone_id
    evaluate_target_health = false
  }
}

# --------------------------
# Secrets Manager (HEC Token)
# --------------------------
resource "aws_secretsmanager_secret" "splunk_hec_token" {
  name = "${local.name_prefix}/splunk-hec-token"
  tags = local.tags
}

# (Add a secret version out-of-band or via aws_secretsmanager_secret_version)

# --------------------------
# Lambda Execution Role
# --------------------------
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect = "Allow"
    principals { type = "Service" identifiers = ["lambda.amazonaws.com"] }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${local.name_prefix}-lambda-exec"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.tags
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "kinesis:GetRecords","kinesis:GetShardIterator","kinesis:DescribeStream","kinesis:ListShards"
    ]
    resources = [aws_kinesis_stream.cwlogs.arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.splunk_hec_token.arn]
  }

  # Allow reading optional CA bundle in S3 (if you pass ca_bundle_s3_arn)
  dynamic "statement" {
    for_each = var.ca_bundle_s3_arn == null ? [] : [1]
    content {
      effect    = "Allow"
      actions   = ["s3:GetObject"]
      resources = [var.ca_bundle_s3_arn]
    }
  }
}

resource "aws_iam_role_policy" "lambda_inline" {
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.lambda_policy.json
}

# --------------------------
# Lambda networking
# --------------------------
resource "aws_security_group" "lambda_sg" {
  name        = "${local.name_prefix}-lambda-sg"
  description = "Lambda egress to VPCE (443)"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # tighten if desired
  }
  tags = local.tags
}

# --------------------------
# Package Lambda from local file
# --------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda/build.zip"
}

resource "aws_lambda_function" "kinesis_to_splunk" {
  function_name = var.lambda_function_name
  role          = aws_iam_role.lambda_exec.arn
  filename      = data.archive_file.lambda_zip.output_path
  handler       = "app.handler"
  runtime       = "python3.12"
  memory_size   = var.lambda_memory_mb
  timeout       = var.lambda_timeout_sec

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      # If Splunk enabled Private DNS, you can use the canonical HEC URL here directly.
      # If not, set splunk_private_dns_enabled=false and provide splunk_hec_hostname above.
      SPLUNK_HEC_URL              = "https://${var.splunk_hec_hostname != null ? var.splunk_hec_hostname : "http-inputs.splunk.local"}:8088"
      SPLUNK_HEC_TOKEN_SECRET_ARN = aws_secretsmanager_secret.splunk_hec_token.arn
      SPLUNK_INDEX                = var.splunk_index
      SPLUNK_SOURCETYPE           = var.splunk_sourcetype
      SPLUNK_SOURCE               = var.splunk_source
      VERIFY_TLS                  = "true"
      CA_BUNDLE_PATH              = "" # leave empty unless you attach and reference a custom CA
    }
  }

  depends_on = [aws_vpc_endpoint.splunk_hec]
  tags       = local.tags
}

resource "aws_lambda_event_source_mapping" "kinesis_trigger" {
  event_source_arn                   = aws_kinesis_stream.cwlogs.arn
  function_name                      = aws_lambda_function.kinesis_to_splunk.arn
  batch_size                         = var.lambda_batch_size
  maximum_batching_window_in_seconds = var.lambda_max_batching_window_sec
  starting_position                  = "LATEST"
  parallelization_factor             = var.lambda_parallelization_factor
  maximum_retry_attempts             = var.lambda_max_retry
  bisect_batch_on_function_error     = true
  tumbling_window_in_seconds         = 0
}