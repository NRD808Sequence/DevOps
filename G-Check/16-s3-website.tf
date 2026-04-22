############################################
# Public S3 Bucket — Deliverables Website
# Hosts pipeline screenshots and deliverables
# for class submission access.
############################################

resource "aws_s3_bucket" "vandelay_deliverables" {
  bucket = "${local.name_prefix}-deliverables-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-deliverables"
  })
}

############################################
# Remove all public access blocks
############################################

resource "aws_s3_bucket_public_access_block" "vandelay_deliverables_pab" {
  bucket = aws_s3_bucket.vandelay_deliverables.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_ownership_controls" "vandelay_deliverables_ownership" {
  bucket = aws_s3_bucket.vandelay_deliverables.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }

  depends_on = [aws_s3_bucket_public_access_block.vandelay_deliverables_pab]
}

############################################
# Static website configuration
############################################

resource "aws_s3_bucket_website_configuration" "vandelay_deliverables_website" {
  bucket = aws_s3_bucket.vandelay_deliverables.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

############################################
# Bucket policy — public read
############################################

resource "aws_s3_bucket_policy" "vandelay_deliverables_policy" {
  bucket = aws_s3_bucket.vandelay_deliverables.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.vandelay_deliverables.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.vandelay_deliverables_pab]
}

############################################
# Objects — index page + all deliverable screenshots
#
# fileset() walks _deliverables/**/*.png at plan time and returns
# a set of relative paths (e.g. "2026-04-13/screenshots/foo.png").
# for_each creates one aws_s3_object per file — Terraform detects
# changes via etag so only new/modified files are re-uploaded.
############################################

resource "aws_s3_object" "vandelay_deliverables_index" {
  bucket       = aws_s3_bucket.vandelay_deliverables.id
  key          = "index.html"
  source       = "${path.module}/website/index.html"
  content_type = "text/html"
  etag         = filemd5("${path.module}/website/index.html")

  depends_on = [aws_s3_bucket_policy.vandelay_deliverables_policy]
}

locals {
  deliverable_screenshots = fileset("${path.module}/_deliverables", "**/*.png")
}

resource "aws_s3_object" "deliverable_screenshots" {
  for_each = local.deliverable_screenshots

  bucket       = aws_s3_bucket.vandelay_deliverables.id
  key          = "deliverables/${each.value}"
  source       = "${path.module}/_deliverables/${each.value}"
  content_type = "image/png"
  etag         = filemd5("${path.module}/_deliverables/${each.value}")

  depends_on = [aws_s3_bucket_policy.vandelay_deliverables_policy]
}

############################################
# Outputs
############################################

output "vandelay_deliverables_bucket" {
  description = "Public deliverables S3 bucket name"
  value       = aws_s3_bucket.vandelay_deliverables.id
}

output "vandelay_deliverables_website_url" {
  description = "Static website URL for the deliverables bucket"
  value       = "http://${aws_s3_bucket.vandelay_deliverables.bucket}.s3-website-${var.aws_region}.amazonaws.com"
}
