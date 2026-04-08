############################################
# Lab 2A: Origin Cloaking
# Makes the ALB invisible to the public -
# ONLY CloudFront can talk to it
############################################

############################################
# AWS Managed Prefix List for CloudFront IPs
############################################

# This is a list AWS maintains of all CloudFront edge server IPs
# We use it to ONLY allow traffic from CloudFront to our ALB
data "aws_ec2_managed_prefix_list" "vandelay_cf_origin_facing01" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

############################################
# Security Group Rule: CloudFront -> ALB Only
############################################

# This rule says: "Only CloudFront's IP addresses can reach the ALB on port 80"
# Direct attacks to the ALB DNS name will be blocked by the security group
resource "aws_security_group_rule" "vandelay_alb_ingress_cf80" {
  type              = "ingress"
  security_group_id = aws_security_group.vandelay_alb_sg01.id
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"

  # Only allow the CloudFront IP ranges
  prefix_list_ids = [
    data.aws_ec2_managed_prefix_list.vandelay_cf_origin_facing01.id
  ]

  description = "Allow HTTP from CloudFront origin-facing IPs only"
}

############################################
# The Secret Handshake (Origin Header)
############################################

# Generate a random 32-character secret that CloudFront adds to every request
# This is like a password that proves the request came from YOUR CloudFront
resource "random_password" "vandelay_origin_secret01" {
  length  = 32
  special = false
}

############################################
# ALB Listener Rules: Validate the Secret
############################################

# Rule 1: If the request HAS the secret header, forward it to the app
resource "aws_lb_listener_rule" "vandelay_require_origin_header01" {
  listener_arn = aws_lb_listener.vandelay_http_listener.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vandelay_tg01.arn
  }

  condition {
    http_header {
      http_header_name = "X-Vandelay-Secret"
      values           = [random_password.vandelay_origin_secret01.result]
    }
  }
}

# Rule 2: If the request does NOT have the secret header, return 403 Forbidden
# This catches anyone trying to bypass CloudFront and hit the ALB directly
resource "aws_lb_listener_rule" "vandelay_default_block01" {
  listener_arn = aws_lb_listener.vandelay_http_listener.arn
  priority     = 99

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden - Access denied"
      status_code  = "403"
    }
  }

  # Catch-all: any path that doesn't have the secret header
  condition {
    path_pattern { values = ["*"] }
  }
}

############################################
# Outputs
############################################

output "vandelay_origin_cloaking_enabled" {
  description = "Origin cloaking is active - ALB only accepts CloudFront traffic"
  value       = true
}
