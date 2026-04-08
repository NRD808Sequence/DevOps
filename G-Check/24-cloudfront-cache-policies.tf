############################################
# Lab 2B: Cache Correctness
# Different content types need different
# caching strategies
############################################

############################################
# 1) Cache Policy: Static Content (Aggressive)
############################################

# Static files (CSS, JS, images) rarely change and are the same for everyone
# Cache them aggressively for maximum speed
resource "aws_cloudfront_cache_policy" "vandelay_cache_static01" {
  name        = "${local.name_prefix}-cache-static01"
  comment     = "Aggressive caching for /static/* - 1 day default, 1 year max"
  default_ttl = 86400    # 1 day (in seconds)
  max_ttl     = 31536000 # 1 year (in seconds)
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    # Don't vary cache by cookies - a PNG is the same regardless of who views it
    cookies_config {
      cookie_behavior = "none"
    }

    # Don't vary cache by query strings (unless you do ?v=1.2.3 versioning)
    query_strings_config {
      query_string_behavior = "none"
    }

    # Don't vary cache by headers - maximizes cache hit ratio
    headers_config {
      header_behavior = "none"
    }

    # Enable compression for faster delivery
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
  }
}

############################################
# 2) Cache Policy: API (Disabled by Default)
############################################

# APIs are DANGEROUS to cache - imagine caching User A's data and serving it to User B!
# Use AWS managed "CachingDisabled" policy instead of custom policy
# This is the recommended approach when you want NO caching
data "aws_cloudfront_cache_policy" "vandelay_caching_disabled" {
  name = "Managed-CachingDisabled"
}

############################################
# 3) Origin Request Policy: API
############################################

# This controls what CloudFront SENDS to your origin (ALB)
# Use AWS managed "AllViewerExceptHostHeader" policy - forwards everything needed
# Note: Authorization header is automatically forwarded, cannot be in custom policy
data "aws_cloudfront_origin_request_policy" "vandelay_orp_all_viewer" {
  name = "Managed-AllViewerExceptHostHeader"
}

############################################
# 4) Origin Request Policy: Static
############################################

# Static content needs almost nothing forwarded - keeps it simple
resource "aws_cloudfront_origin_request_policy" "vandelay_orp_static01" {
  name    = "${local.name_prefix}-orp-static01"
  comment = "Minimal forwarding for static assets"

  cookies_config {
    cookie_behavior = "none"
  }

  query_strings_config {
    query_string_behavior = "none"
  }

  headers_config {
    header_behavior = "none"
  }
}

############################################
# 5) Response Headers Policy: Static
############################################

# Add explicit Cache-Control header so browsers AND CloudFront agree on caching
resource "aws_cloudfront_response_headers_policy" "vandelay_rsp_static01" {
  name    = "${local.name_prefix}-rsp-static01"
  comment = "Add explicit Cache-Control for static content"

  custom_headers_config {
    items {
      header   = "Cache-Control"
      override = true
      value    = "public, max-age=86400, immutable"
    }
  }
}

############################################
# Outputs
############################################

output "vandelay_cache_policy_static_id" {
  description = "Cache policy ID for static content"
  value       = aws_cloudfront_cache_policy.vandelay_cache_static01.id
}

output "vandelay_cache_policy_api_id" {
  description = "Cache policy ID for API (disabled)"
  value       = data.aws_cloudfront_cache_policy.vandelay_caching_disabled.id
}
