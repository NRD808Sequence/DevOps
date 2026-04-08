############################################
# Lab 2A: CloudFront WAF
# WAF at the edge - blocks attacks BEFORE
# they even reach your VPC
############################################

# IMPORTANT: CloudFront WAF must be in us-east-1 and scope = "CLOUDFRONT"
# This is different from ALB WAF which uses scope = "REGIONAL"

resource "aws_wafv2_web_acl" "vandelay_cf_waf01" {
  provider = aws # Must be us-east-1 for CloudFront

  name        = "${local.name_prefix}-cf-waf01"
  description = "CloudFront WAF for Vandelay Industries"
  scope       = "CLOUDFRONT" # This is the key difference from ALB WAF

  default_action {
    allow {}
  }

  # Rule 1: Block known malicious IPs (botnets, scanners, etc.)
  rule {
    name     = "AWS-AWSManagedRulesAmazonIpReputationList"
    priority = 0

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-cf-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: Common attack patterns (XSS, path traversal, etc.)
  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-cf-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # Rule 3: Known bad inputs (Log4j, Spring4Shell, etc.)
  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-cf-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # Rule 4: SQL injection attacks
  rule {
    name     = "AWS-AWSManagedRulesSQLiRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-cf-sqli-rules"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-cf-waf"
    sampled_requests_enabled   = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cf-waf01"
  })
}

############################################
# Outputs
############################################

output "vandelay_cf_waf_arn" {
  description = "CloudFront WAF Web ACL ARN"
  value       = aws_wafv2_web_acl.vandelay_cf_waf01.arn
}
