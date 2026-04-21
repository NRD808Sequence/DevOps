############################################
# CloudTrail — AWS API Audit Log
# H3 — OWASP A09: Security Logging & Monitoring
#
# Records all management API calls in us-east-1:
#   IAM changes, EC2 start/stop, S3 access,
#   Secrets Manager reads, RDS events, etc.
#
# Answers: "who did what, when, from where?"
############################################

# Dedicated S3 bucket for CloudTrail logs.
# Must NOT be the website or deliverables bucket —
# CloudTrail requires a specific service principal bucket policy.
resource "aws_s3_bucket" "vandelay_cloudtrail" {
  bucket        = "vandelay-cloudtrail-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cloudtrail-logs"
  })
}

resource "aws_s3_bucket_public_access_block" "vandelay_cloudtrail" {
  bucket = aws_s3_bucket.vandelay_cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "vandelay_cloudtrail" {
  bucket = aws_s3_bucket.vandelay_cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "vandelay_cloudtrail" {
  bucket = aws_s3_bucket.vandelay_cloudtrail.id
  versioning_configuration {
    status = "Enabled"
  }
}

# CloudTrail requires two specific statements:
#   1. s3:GetBucketAcl — CloudTrail checks it can write before starting
#   2. s3:PutObject    — CloudTrail writes log files under AWSLogs/<account-id>/
resource "aws_s3_bucket_policy" "vandelay_cloudtrail" {
  bucket = aws_s3_bucket.vandelay_cloudtrail.id

  # Block public access must be applied before a bucket policy can be set
  depends_on = [aws_s3_bucket_public_access_block.vandelay_cloudtrail]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.vandelay_cloudtrail.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.vandelay_cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

############################################
# CloudTrail
############################################

resource "aws_cloudtrail" "vandelay_trail" {
  name           = "${local.name_prefix}-trail"
  s3_bucket_name = aws_s3_bucket.vandelay_cloudtrail.id

  # Capture IAM, STS, and other global service events
  # (e.g., who created/deleted an IAM user or access key)
  include_global_service_events = true

  # Single-region trail covers us-east-1 where all lab-2 resources live.
  # Set true in a real environment to catch cross-region activity.
  is_multi_region_trail = false

  # SHA-256 digest file written alongside each log batch.
  # Detects if log files have been tampered with or deleted.
  enable_log_file_validation = true

  # Bucket policy must exist before CloudTrail can verify write access
  depends_on = [aws_s3_bucket_policy.vandelay_cloudtrail]

  tags = local.common_tags
}

############################################
# Outputs
############################################

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail"
  value       = aws_cloudtrail.vandelay_trail.arn
}

output "cloudtrail_bucket" {
  description = "S3 bucket receiving CloudTrail logs"
  value       = aws_s3_bucket.vandelay_cloudtrail.id
}
