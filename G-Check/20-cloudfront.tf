############################################
# Lab 2A: CloudFront Distribution
# CloudFront becomes the ONLY public doorway
# to your application - the ALB hides behind it
############################################

############################################
# CloudFront Distribution
############################################

resource "aws_cloudfront_distribution" "vandelay_cf01" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${local.name_prefix}-cf01"

  # The ALB is the "origin" - where CloudFront fetches content from
  origin {
    origin_id   = "${local.name_prefix}-alb-origin01"
    domain_name = aws_lb.vandelay_alb01.dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # Use HTTP to ALB (secret header provides security)
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # THE SECRET HANDSHAKE: CloudFront adds this header to every request
    # The ALB will ONLY accept requests that have this header
    custom_header {
      name  = "X-Vandelay-Secret"
      value = random_password.vandelay_origin_secret01.result
    }
  }

  # Default behavior - applies to all requests unless a more specific pattern matches
  default_cache_behavior {
    target_origin_id       = "${local.name_prefix}-alb-origin01"
    viewer_protocol_policy = "redirect-to-https"

    # Allow all HTTP methods (GET, POST, PUT, DELETE, etc.)
    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]

    # Use AWS managed policies (API = no caching by default)
    cache_policy_id          = data.aws_cloudfront_cache_policy.vandelay_caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.vandelay_orp_all_viewer.id
  }

  # Static content behavior - /static/* gets aggressive caching
  ordered_cache_behavior {
    path_pattern           = "/static/*"
    target_origin_id       = "${local.name_prefix}-alb-origin01"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]

    cache_policy_id            = aws_cloudfront_cache_policy.vandelay_cache_static01.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.vandelay_orp_static01.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.vandelay_rsp_static01.id
  }

  # Attach WAF at CloudFront edge (blocks attacks before they reach your VPC)
  web_acl_id = aws_wafv2_web_acl.vandelay_cf_waf01.arn

  # Both the root domain and app subdomain go through CloudFront
  aliases = [
    var.domain_name,
    "${var.app_subdomain}.${var.domain_name}"
  ]

  # TLS certificate - must be in us-east-1 for CloudFront
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.vandelay_cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  # No geographic restrictions
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cf01"
  })

  depends_on = [aws_acm_certificate_validation.vandelay_cert_validated]
}

############################################
# Outputs
############################################

output "vandelay_cloudfront_domain" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.vandelay_cf01.domain_name
}

output "vandelay_cloudfront_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.vandelay_cf01.id
}
