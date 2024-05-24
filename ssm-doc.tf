provider "aws" {
  region = "us-west-2"
}

# IAM Role for SSM Document
resource "aws_iam_role" "ssm_document_role" {
  name = "ssm_document_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
      },
    ]
  })
}

# IAM Policy for SSM Document Role
resource "aws_iam_policy" "ssm_document_policy" {
  name        = "ssm_document_policy"
  description = "Policy for SSM Document to execute Step Functions"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "states:StartExecution"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# Attach Policy to Role
resource "aws_iam_role_policy_attachment" "ssm_document_policy_attach" {
  role       = aws_iam_role.ssm_document_role.name
  policy_arn = aws_iam_policy.ssm_document_policy.arn
}

data "aws_sfn_state_machine" "example" {
  name = "example-state-machine"
}

# SSM Document
resource "aws_ssm_document" "start_step_function" {
  name          = "StartStepFunctionExecution"
  document_type = "Automation"

  content = <<JSON
{
  "schemaVersion": "0.3",
  "description": "Start an AWS Step Functions execution",
  "parameters": {
    "StateMachineArn": {
      "type": "String",
      "description": "The ARN of the Step Function state machine to execute"
    },
    "Input": {
      "type": "String",
      "default": "{}",
      "description": "Input for the Step Function execution"
    }
  },
  "mainSteps": [
    {
      "action": "aws:executeStepFunction",
      "name": "executeStepFunction",
      "inputs": {
        "StateMachineArn": "{{ StateMachineArn }}",
        "Input": "{{ Input }}"
      }
    }
  ]
}
JSON

  depends_on = [aws_iam_role_policy_attachment.ssm_document_policy_attach]
}

# Usage Example: SSM Automation Execution
resource "aws_ssm_automation_execution" "example" {
  document_name = aws_ssm_document.start_step_function.name

  parameters = {
    StateMachineArn = data.aws_sfn_state_machine.example.arn
    Input           = jsonencode({
      "key1" = "value1"
    })
  }
}