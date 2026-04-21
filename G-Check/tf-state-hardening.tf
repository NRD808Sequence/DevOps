############################################
# TF State Bucket Hardening
# H5 — OWASP A05: Security Misconfiguration
#
# The state bucket (class7-armagaggeon-tf-bucket) was created manually
# as a bootstrap resource — Terraform cannot manage the bucket itself
# without circular dependency.
#
# These resources apply versioning and SSE-KMS encryption to the
# existing bucket without taking ownership of it.
#
# Why this matters:
#   The state file contains: RDS password, X-Vandelay-Secret origin
#   cloaking value, all resource ARNs, and IAM role/policy IDs.
#   Without versioning, state corruption or accidental overwrite is
#   unrecoverable. Without SSE-KMS, any IAM identity with s3:GetObject
#   on the bucket reads all secrets in plaintext.
############################################

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = "class7-armagaggeon-tf-bucket"
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = "class7-armagaggeon-tf-bucket"

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    # bucket_key_enabled reduces KMS request costs by ~99%
    # when many state reads/writes occur (e.g., CI pipeline)
    bucket_key_enabled = true
  }
}
