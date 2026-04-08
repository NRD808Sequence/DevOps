############################################
# WAF Logging Configuration
# IMPORTANT: Log group name MUST start with "aws-waf-logs-"
# This is an AWS requirement - other names silently fail!
############################################

############################################
# CloudWatch Log Group for WAF Logs
############################################

resource "aws_cloudwatch_log_group" "vandelay_waf_logs" {
  # AWS REQUIRES this prefix - do not change!
  name              = "aws-waf-logs-${local.name_prefix}-webacl"
  retention_in_days = var.waf_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-waf-logs"
  })
}

############################################
# WAF Logging Configuration
############################################

resource "aws_wafv2_web_acl_logging_configuration" "vandelay_waf_logging" {
  log_destination_configs = [aws_cloudwatch_log_group.vandelay_waf_logs.arn]
  resource_arn            = aws_wafv2_web_acl.vandelay_waf01.arn

  # Optional: Redact sensitive fields from logs
  # Uncomment to redact authorization headers
  # redacted_fields {
  #   single_header {
  #     name = "authorization"
  #   }
  # }

  # Optional: Filter which requests to log
  # Uncomment to only log blocked requests (reduces log volume)
  # logging_filter {
  #   default_behavior = "DROP"
  #   filter {
  #     behavior    = "KEEP"
  #     requirement = "MEETS_ANY"
  #     condition {
  #       action_condition {
  #         action = "BLOCK"
  #       }
  #     }
  #   }
  # }
}

############################################
# CloudWatch Log Insights Sample Queries
# (For reference - use in CloudWatch Console)
############################################

# Query 1: Count of ALLOW vs BLOCK actions
# fields @timestamp, action
# | stats count() as hits by action
# | sort hits desc

# Query 2: Top blocked IPs
# fields @timestamp, action, httpRequest.clientIp as clientIp
# | filter action = "BLOCK"
# | stats count() as blocks by clientIp
# | sort blocks desc
# | limit 25

# Query 3: Top blocked URIs
# fields @timestamp, action, httpRequest.uri as uri
# | filter action = "BLOCK"
# | stats count() as blocks by uri
# | sort blocks desc
# | limit 25

# Query 4: Top terminating rules
# fields @timestamp, terminatingRuleId
# | filter action = "BLOCK"
# | stats count() as blocks by terminatingRuleId
# | sort blocks desc

############################################
# Outputs
############################################

output "vandelay_waf_log_group_name" {
  description = "WAF CloudWatch Log Group name"
  value       = aws_cloudwatch_log_group.vandelay_waf_logs.name
}

output "vandelay_waf_log_group_arn" {
  description = "WAF CloudWatch Log Group ARN"
  value       = aws_cloudwatch_log_group.vandelay_waf_logs.arn
}
