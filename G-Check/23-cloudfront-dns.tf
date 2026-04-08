############################################
# Lab 2A: CloudFront DNS Records
# DNS now points to CloudFront, NOT the ALB
# This completes the "origin cloaking" setup
############################################

# IMPORTANT: These records REPLACE the Lab 1 records that pointed to ALB
# After applying this, all traffic goes: User -> CloudFront -> ALB -> EC2

############################################
# Root Domain -> CloudFront
############################################

# keepuneat.click now points to CloudFront (was: ALB)
resource "aws_route53_record" "vandelay_apex_to_cf01" {
  zone_id = local.vandelay_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.vandelay_cf01.domain_name
    zone_id                = aws_cloudfront_distribution.vandelay_cf01.hosted_zone_id
    evaluate_target_health = false # CloudFront handles health itself
  }
}

############################################
# App Subdomain -> CloudFront
############################################

# app.keepuneat.click also points to CloudFront (was: ALB)
resource "aws_route53_record" "vandelay_app_to_cf01" {
  zone_id = local.vandelay_zone_id
  name    = "${var.app_subdomain}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.vandelay_cf01.domain_name
    zone_id                = aws_cloudfront_distribution.vandelay_cf01.hosted_zone_id
    evaluate_target_health = false
  }
}

############################################
# Outputs
############################################

output "vandelay_app_url_via_cloudfront" {
  description = "Application URL (now served via CloudFront)"
  value       = "https://${var.app_subdomain}.${var.domain_name}"
}

output "vandelay_root_url_via_cloudfront" {
  description = "Root domain URL (now served via CloudFront)"
  value       = "https://${var.domain_name}"
}
