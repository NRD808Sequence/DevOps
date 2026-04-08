############################################
# Bonus-B: Production-Grade ALB + TLS + WAF
############################################

############################################
# Route53 Hosted Zone - USE EXISTING
############################################

data "aws_route53_zone" "vandelay_zone" {
  name         = var.domain_name
  private_zone = false
}

locals {
  vandelay_zone_id  = data.aws_route53_zone.vandelay_zone.zone_id
  vandelay_app_fqdn = "${var.app_subdomain}.${var.domain_name}"
}

############################################
# ACM Certificate
############################################

resource "aws_acm_certificate" "vandelay_cert" {
  domain_name               = local.vandelay_app_fqdn
  subject_alternative_names = ["*.${var.domain_name}", var.domain_name] # Include root domain for CloudFront
  validation_method         = "DNS"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-acm-cert"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "vandelay_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.vandelay_cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = local.vandelay_zone_id
}

resource "aws_acm_certificate_validation" "vandelay_cert_validated" {
  certificate_arn         = aws_acm_certificate.vandelay_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.vandelay_cert_validation : record.fqdn]

  timeouts {
    create = "5m"
  }
}

############################################
# ALB Security Group
############################################

resource "aws_security_group" "vandelay_alb_sg01" {
  name        = "${local.name_prefix}-alb-sg01"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.vandelay_vpc01.id

  # DISABLED: Lab 2 restricts ALB access to CloudFront IPs only
  # See 21-cloudfront-origin-cloaking.tf for CloudFront prefix list rule
  # ingress {
  #   from_port   = 80
  #   to_port     = 80
  #   protocol    = "tcp"
  #   cidr_blocks = [var.alb_ingress_cidr]
  #   description = "Allow HTTP from internet"
  # }

  # ingress {
  #   from_port   = 443
  #   to_port     = 443
  #   protocol    = "tcp"
  #   cidr_blocks = [var.alb_ingress_cidr]
  #   description = "Allow HTTPS from internet"
  # }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-sg01"
  })
}

############################################
# Application Load Balancer
############################################

resource "aws_lb" "vandelay_alb01" {
  name               = "${local.name_prefix}-alb01"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.vandelay_alb_sg01.id]
  subnets            = aws_subnet.vandelay_public_subnets[*].id

  enable_deletion_protection = false

  # ALB Access Logs (enabled via variable)
  dynamic "access_logs" {
    for_each = var.enable_alb_access_logs ? [1] : []
    content {
      bucket  = aws_s3_bucket.vandelay_alb_logs[0].id
      prefix  = var.alb_access_logs_prefix
      enabled = true
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb01"
  })
}

############################################
# Target Group
############################################

resource "aws_lb_target_group" "vandelay_tg01" {
  name     = "${local.name_prefix}-tg01"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vandelay_vpc01.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-tg01"
  })
}

resource "aws_lb_target_group_attachment" "vandelay_tg_attachment01" {
  target_group_arn = aws_lb_target_group.vandelay_tg01.arn
  target_id        = aws_instance.vandelay_ec201.id
  port             = 80
}

############################################
# ALB Listeners
############################################

resource "aws_lb_listener" "vandelay_https_listener" {
  load_balancer_arn = aws_lb.vandelay_alb01.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.vandelay_cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vandelay_tg01.arn
  }

  depends_on = [aws_acm_certificate_validation.vandelay_cert_validated]
}

resource "aws_lb_listener" "vandelay_http_listener" {
  load_balancer_arn = aws_lb.vandelay_alb01.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

############################################
# Route53 DNS Record for App
# DISABLED: Lab 2 redirects DNS to CloudFront
# See 23-cloudfront-dns.tf for CloudFront DNS
############################################

# resource "aws_route53_record" "vandelay_app_alias01" {
#   zone_id = local.vandelay_zone_id
#   name    = local.vandelay_app_fqdn
#   type    = "A"
#
#   alias {
#     name                   = aws_lb.vandelay_alb01.dns_name
#     zone_id                = aws_lb.vandelay_alb01.zone_id
#     evaluate_target_health = true
#   }
# }

############################################
# Route53 Zone Apex (Root Domain) -> ALB
# DISABLED: Lab 2 redirects DNS to CloudFront
############################################

# resource "aws_route53_record" "vandelay_apex_alias" {
#   zone_id = local.vandelay_zone_id
#   name    = var.domain_name  # Root domain (e.g., keepuneat.click)
#   type    = "A"
#
#   alias {
#     name                   = aws_lb.vandelay_alb01.dns_name
#     zone_id                = aws_lb.vandelay_alb01.zone_id
#     evaluate_target_health = true
#   }
# }

############################################
# WAF Web ACL
############################################

resource "aws_wafv2_web_acl" "vandelay_waf01" {
  name        = "${local.name_prefix}-waf01"
  description = "WAF for Vandelay ALB"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # IP Reputation List - blocks known malicious IPs (scanners, botnets, etc.)
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
      metric_name                = "${local.name_prefix}-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

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
      metric_name                = "${local.name_prefix}-common-rules"
      sampled_requests_enabled   = true
    }
  }

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
      metric_name                = "${local.name_prefix}-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

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
      metric_name                = "${local.name_prefix}-sqli-rules"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-waf"
    sampled_requests_enabled   = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-waf01"
  })
}

resource "aws_wafv2_web_acl_association" "vandelay_waf_alb_assoc" {
  resource_arn = aws_lb.vandelay_alb01.arn
  web_acl_arn  = aws_wafv2_web_acl.vandelay_waf01.arn
}

############################################
# CloudWatch Dashboard
############################################

resource "aws_cloudwatch_dashboard" "vandelay_dashboard01" {
  dashboard_name = "${local.name_prefix}-dashboard01"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ALB Request Count"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.vandelay_alb01.arn_suffix]
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ALB HTTP 5xx Errors"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", aws_lb.vandelay_alb01.arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.vandelay_alb01.arn_suffix]
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Target Response Time"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.vandelay_alb01.arn_suffix]
          ]
          period = 300
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Healthy Host Count"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", aws_lb_target_group.vandelay_tg01.arn_suffix, "LoadBalancer", aws_lb.vandelay_alb01.arn_suffix]
          ]
          period = 300
          stat   = "Average"
        }
      }
    ]
  })
}

############################################
# CloudWatch Alarm - ALB 5xx Errors
############################################

resource "aws_cloudwatch_metric_alarm" "vandelay_alb_5xx_alarm" {
  alarm_name          = "${local.name_prefix}-alb-5xx-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "ALB 5xx errors exceeded threshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.vandelay_alb01.arn_suffix
  }

  alarm_actions = [aws_sns_topic.vandelay_sns_topic01.arn]
  ok_actions    = [aws_sns_topic.vandelay_sns_topic01.arn]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-5xx-alarm"
  })
}
