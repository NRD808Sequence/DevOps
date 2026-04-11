############################################
# Jenkins ALB — HTTPS via existing wildcard ACM cert
# URL: https://jenkins.keepuneat.click
############################################

############################################
# Jenkins ALB Security Group
############################################

resource "aws_security_group" "vandelay_jenkins_alb_sg" {
  name        = "${local.name_prefix}-jenkins-alb-sg"
  description = "Security group for Jenkins ALB - public HTTPS/HTTP"
  vpc_id      = aws_vpc.vandelay_vpc01.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from internet"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from internet (redirects to HTTPS)"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-jenkins-alb-sg"
  })
}

############################################
# Update Jenkins EC2 SG — restrict 8080 to ALB only
############################################

resource "aws_security_group_rule" "vandelay_jenkins_from_alb" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = aws_security_group.vandelay_jenkins_sg.id
  source_security_group_id = aws_security_group.vandelay_jenkins_alb_sg.id
  description              = "Allow Jenkins UI from ALB only"
}

############################################
# Jenkins ALB
############################################

resource "aws_lb" "vandelay_jenkins_alb" {
  name               = "${local.name_prefix}-jenkins-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.vandelay_jenkins_alb_sg.id]
  subnets            = aws_subnet.vandelay_public_subnets[*].id

  enable_deletion_protection = false

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-jenkins-alb"
  })
}

############################################
# Target Group — Jenkins on port 8080
############################################

resource "aws_lb_target_group" "vandelay_jenkins_tg" {
  name     = "${local.name_prefix}-jenkins-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.vandelay_vpc01.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/login"
    protocol            = "HTTP"
    matcher             = "200"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-jenkins-tg"
  })
}

resource "aws_lb_target_group_attachment" "vandelay_jenkins_tg_attachment" {
  target_group_arn = aws_lb_target_group.vandelay_jenkins_tg.arn
  target_id        = aws_instance.vandelay_jenkins.id
  port             = 8080
}

############################################
# Listeners
############################################

resource "aws_lb_listener" "vandelay_jenkins_https" {
  load_balancer_arn = aws_lb.vandelay_jenkins_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.vandelay_cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vandelay_jenkins_tg.arn
  }

  depends_on = [aws_acm_certificate_validation.vandelay_cert_validated]
}

resource "aws_lb_listener" "vandelay_jenkins_http_redirect" {
  load_balancer_arn = aws_lb.vandelay_jenkins_alb.arn
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
# Route53 — jenkins.keepuneat.click → ALB
############################################

resource "aws_route53_record" "vandelay_jenkins_dns" {
  zone_id = local.vandelay_zone_id
  name    = "jenkins.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.vandelay_jenkins_alb.dns_name
    zone_id                = aws_lb.vandelay_jenkins_alb.zone_id
    evaluate_target_health = true
  }
}
