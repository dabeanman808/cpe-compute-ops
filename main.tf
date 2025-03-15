# DynamoDB Table
resource "aws_dynamodb_table" "resource_schedules" {
  name           = "resource_schedules"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "ResourceID"

  attribute {
    name = "ResourceID"
    type = "S"
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name               = "lambda_schedules_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# Policy to allow SSM invocation & DynamoDB
resource "aws_iam_role_policy" "lambda_policy" {
  name   = "lambda_schedules_policy"
  role   = aws_iam_role.lambda_role.id
  policy = data.aws_iam_policy_document.lambda_inline.json
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda_inline" {
  statement {
    actions   = ["dynamodb:Query", "dynamodb:Scan", "dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.resource_schedules.arn]
  }
  statement {
    actions = [
      "ssm:StartAutomationExecution",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }
}

# Lambda Function
resource "aws_lambda_function" "schedule_lambda" {
  function_name = "schedule-controller"
  runtime       = "python3.9"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"

  # Minimal, codeless approach if possible, or a short Python script that calls SSM.
  filename      = "${path.module}/schedule_lambda.zip"
  # Alternatively, inline code with local_file data source.

  environment {
    variables = {
      DDB_TABLE = aws_dynamodb_table.resource_schedules.name
    }
  }
}

# EventBridge Rule for Scheduling
resource "aws_cloudwatch_event_rule" "schedule_rule" {
  name        = "compute-daily-shutdown-startup"
  description = "Triggers Lambda to manage schedules"
  schedule_expression = "cron(0 * * * ? *)" # runs every hour
}

resource "aws_cloudwatch_event_target" "schedule_target" {
  rule      = aws_cloudwatch_event_rule.schedule_rule.name
  target_id = "schedule-lambda"
  arn       = aws_lambda_function.schedule_lambda.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.schedule_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule_rule.arn
}

# SSM Automation Runbook (Automation Document)
resource "aws_ssm_document" "start_stop_runbook" {
  name          = "StartStopInstancesRunbook"
  document_type = "Automation"
  content = <<EOF
{
  "schemaVersion": "0.3",
  "description": "Runbook to start or stop EC2 instances",
  "parameters": {
    "InstanceId": {
      "type": "String",
      "description": "EC2 instance to start or stop"
    },
    "Action": {
      "type": "String",
      "description": "Running or Stopped"
    }
  },
  "mainSteps": [
    {
      "name": "changeInstanceState",
      "action": "aws:changeInstanceState",
      "inputs": {
        "InstanceIds": ["{{ InstanceId }}"],
        "DesiredState": "{{ Action }}"
      }
    }
  ]
}
EOF
}

# Assuming you have already defined:
# resource "aws_dynamodb_table" "resource_schedules" {...}

resource "aws_dynamodb_table_item" "ec2_dev_item" {
  table_name = aws_dynamodb_table.resource_schedules.name
  hash_key   = "ResourceID"

  # The 'item' block must use DynamoDB's attribute-value JSON format
  item = <<ITEM
{
  "ResourceID": { "S": "debianaws" },
  "EC2InstanceId": { "S": "i-0f3c590bcda996cf9" },
  "ShutdownTime": { "S": "22:00" },
  "StartupTime": { "S": "07:00" }
}
ITEM
}
