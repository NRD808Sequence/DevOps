############################################
# Incident Reporter Lambda (Claude/Bedrock)
# Comprehensive version with Logs Insights,
# S3 storage, and structured reports
############################################

# S3 Bucket for Incident Reports
resource "aws_s3_bucket" "incident_reports" {
  bucket = "${local.name_prefix}-incident-reports-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-incident-reports"
  })

  # Prevent deletion - preserve incident reports across infrastructure rebuilds
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "incident_reports" {
  bucket = aws_s3_bucket.incident_reports.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "incident_reports" {
  bucket = aws_s3_bucket.incident_reports.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "incident_reports" {
  bucket = aws_s3_bucket.incident_reports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Package Lambda code
data "archive_file" "incident_reporter_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda/incident_reporter.zip"
}

# IAM Role for Incident Reporter Lambda
resource "aws_iam_role" "incident_reporter_role" {
  name = "${local.name_prefix}-incident-reporter-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

# Basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "incident_reporter_basic" {
  role       = aws_iam_role.incident_reporter_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Bedrock access policy
resource "aws_iam_role_policy" "incident_reporter_bedrock" {
  name = "${local.name_prefix}-incident-reporter-bedrock"
  role = aws_iam_role.incident_reporter_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockInvoke"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
          "arn:aws:bedrock:${var.aws_region}::foundation-model/anthropic.claude-3-haiku-20240307-v1:0",
          "arn:aws:bedrock:${var.aws_region}::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0",
          "arn:aws:bedrock:${var.aws_region}::foundation-model/anthropic.claude-instant-v1"
        ]
      }
    ]
  })
}

# SNS publish policy
resource "aws_iam_role_policy" "incident_reporter_sns" {
  name = "${local.name_prefix}-incident-reporter-sns"
  role = aws_iam_role.incident_reporter_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SNSPublish"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.vandelay_sns_topic01.arn
      }
    ]
  })
}

# S3 access for storing reports
resource "aws_iam_role_policy" "incident_reporter_s3" {
  name = "${local.name_prefix}-incident-reporter-s3"
  role = aws_iam_role.incident_reporter_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3WriteReports"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.incident_reports.arn,
          "${aws_s3_bucket.incident_reports.arn}/*"
        ]
      }
    ]
  })
}

# CloudWatch Logs Insights query access
resource "aws_iam_role_policy" "incident_reporter_logs" {
  name = "${local.name_prefix}-incident-reporter-logs"
  role = aws_iam_role.incident_reporter_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LogsInsightsQuery"
        Effect = "Allow"
        Action = [
          "logs:StartQuery",
          "logs:GetQueryResults",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:GetLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# SSM Parameter Store read access
resource "aws_iam_role_policy" "incident_reporter_ssm" {
  name = "${local.name_prefix}-incident-reporter-ssm"
  role = aws_iam_role.incident_reporter_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMReadParams"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/lab/*"
      }
    ]
  })
}

# Secrets Manager read access (metadata only)
resource "aws_iam_role_policy" "incident_reporter_secrets" {
  name = "${local.name_prefix}-incident-reporter-secrets"
  role = aws_iam_role.incident_reporter_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = data.aws_secretsmanager_secret.vandelay_db_secret01.arn
      }
    ]
  })
}

# Lambda Function
resource "aws_lambda_function" "incident_reporter" {
  filename         = data.archive_file.incident_reporter_zip.output_path
  function_name    = "${local.name_prefix}-incident-reporter"
  role             = aws_iam_role.incident_reporter_role.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.11"
  timeout          = 120
  memory_size      = 256
  source_code_hash = data.archive_file.incident_reporter_zip.output_base64sha256

  environment {
    variables = {
      BEDROCK_MODEL_ID = "anthropic.claude-3-haiku-20240307-v1:0"
      SNS_TOPIC_ARN    = aws_sns_topic.vandelay_sns_topic01.arn
      REPORT_BUCKET    = aws_s3_bucket.incident_reports.id
      APP_LOG_GROUP    = aws_cloudwatch_log_group.vandelay_log_group01.name
      WAF_LOG_GROUP    = "" # Set to WAF log group name if WAF logging is enabled
      SECRET_ID        = "lab/rds/mysql"
      SSM_PARAM_PATH   = "/lab/db"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-incident-reporter"
  })
}

# Allow SNS to invoke Lambda
resource "aws_lambda_permission" "incident_reporter_sns" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.incident_reporter.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.vandelay_sns_topic01.arn
}

# Subscribe Lambda to SNS topic (triggered by CloudWatch alarms)
resource "aws_sns_topic_subscription" "incident_reporter_sub" {
  topic_arn = aws_sns_topic.vandelay_sns_topic01.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.incident_reporter.arn
}

############################################
# Outputs
############################################

output "incident_reporter_function_name" {
  value       = aws_lambda_function.incident_reporter.function_name
  description = "Incident Reporter Lambda function name"
}

output "incident_reporter_arn" {
  value       = aws_lambda_function.incident_reporter.arn
  description = "Incident Reporter Lambda ARN"
}

output "incident_reports_bucket" {
  value       = aws_s3_bucket.incident_reports.id
  description = "S3 bucket for incident reports"
}
