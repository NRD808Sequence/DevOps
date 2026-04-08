############################################
# ALB Access Logs to S3
# Captures all requests hitting the ALB for
# debugging, forensics, and compliance
############################################

############################################
# S3 Bucket for ALB Access Logs
############################################

resource "aws_s3_bucket" "vandelay_alb_logs" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket = "${local.name_prefix}-alb-logs-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-logs"
  })

  # Prevent deletion - preserve logs across infrastructure rebuilds
  lifecycle {
    prevent_destroy = true
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "vandelay_alb_logs_pab" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket                  = aws_s3_bucket.vandelay_alb_logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning for audit trail
resource "aws_s3_bucket_versioning" "vandelay_alb_logs_versioning" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket = aws_s3_bucket.vandelay_alb_logs[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "vandelay_alb_logs_sse" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket = aws_s3_bucket.vandelay_alb_logs[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Bucket ownership controls
resource "aws_s3_bucket_ownership_controls" "vandelay_alb_logs_owner" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket = aws_s3_bucket.vandelay_alb_logs[0].id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

############################################
# Bucket Policy for ELB Access
############################################

# ELB account IDs per region (us-east-1 = 127311923021)
# Full list: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-access-logging.html
locals {
  elb_account_id = {
    "us-east-1"      = "127311923021"
    "us-east-2"      = "033677994240"
    "us-west-1"      = "027434742980"
    "us-west-2"      = "797873946194"
    "eu-west-1"      = "156460612806"
    "eu-west-2"      = "652711504416"
    "eu-central-1"   = "054676820928"
    "ap-southeast-1" = "114774131450"
    "ap-southeast-2" = "783225319266"
    "ap-northeast-1" = "582318560864"
  }
}

resource "aws_s3_bucket_policy" "vandelay_alb_logs_policy" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket = aws_s3_bucket.vandelay_alb_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.vandelay_alb_logs[0].arn,
          "${aws_s3_bucket.vandelay_alb_logs[0].arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
      {
        Sid    = "AllowELBRootAcl"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.elb_account_id[var.aws_region]}:root"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.vandelay_alb_logs[0].arn}/${var.alb_access_logs_prefix}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      },
      {
        Sid    = "AllowELBLogDelivery"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.vandelay_alb_logs[0].arn}/${var.alb_access_logs_prefix}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "AllowELBLogDeliveryAcl"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.vandelay_alb_logs[0].arn
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.vandelay_alb_logs_pab]
}

############################################
# Lifecycle Rule - Auto-expire old logs
############################################

resource "aws_s3_bucket_lifecycle_configuration" "vandelay_alb_logs_lifecycle" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket = aws_s3_bucket.vandelay_alb_logs[0].id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {
      prefix = "" # Apply to all objects
    }

    expiration {
      days = var.alb_logs_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

############################################
# Outputs
############################################

output "vandelay_alb_logs_bucket" {
  description = "ALB access logs S3 bucket name"
  value       = var.enable_alb_access_logs ? aws_s3_bucket.vandelay_alb_logs[0].id : null
}

output "vandelay_alb_logs_bucket_arn" {
  description = "ALB access logs S3 bucket ARN"
  value       = var.enable_alb_access_logs ? aws_s3_bucket.vandelay_alb_logs[0].arn : null
}
