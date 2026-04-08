############################################
# Bonus A - Data + Locals
############################################

# Explanation: Vandelay wants to know "who am I in this galaxy?" so ARNs can be scoped properly.
data "aws_caller_identity" "vandelay_self01" {}

# Explanation: Region matters—hyperspace lanes change per sector.
data "aws_region" "vandelay_region01" {}

locals {
  # Explanation: Name prefix is the roar that echoes through every tag.
  vandelay_prefix = var.project_name

  # Reference the existing secret ARN from data source
  vandelay_secret_arn = data.aws_secretsmanager_secret.vandelay_db_secret01.arn
}

############################################
# Move EC2 into PRIVATE subnet (no public IP)
############################################

# Explanation: Vandelay hates exposure—private subnets keep your compute off the public holonet.
resource "aws_instance" "vandelay_ec201_private_bonus" {
  ami                    = var.ec2_ami_id
  instance_type          = var.ec2_instance_type
  subnet_id              = aws_subnet.vandelay_private_subnets[0].id
  vpc_security_group_ids = [aws_security_group.vandelay_ec2_sg01.id]
  iam_instance_profile   = aws_iam_instance_profile.vandelay_instance_profile01.name

  user_data = file("${path.module}/user_data.sh")

  # TODO: Students should remove/disable SSH inbound rules entirely and rely on SSM.

  tags = {
    Name = "${local.name_prefix}-ec201-private"
  }
}

############################################
# Security Group for VPC Interface Endpoints
############################################

# Explanation: Even endpoints need guards—Vandelay posts a guard at every airlock.
resource "aws_security_group" "vandelay_vpce_sg01" {
  name        = "${local.name_prefix}-vpce-sg01"
  description = "SG for VPC Interface Endpoints"
  vpc_id      = aws_vpc.vandelay_vpc01.id

  # Allow inbound 443 from EC2 SG to endpoints
  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    security_groups = [
      aws_security_group.vandelay_ec2_sg01.id,
      aws_security_group.rotation_lambda_sg.id,
      aws_security_group.vandelay_jenkins_sg.id
    ]
    description = "Allow HTTPS from EC2, Lambda, and Jenkins"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpce-sg01"
  })
}

############################################
# VPC Endpoint - S3 (Gateway)
############################################

# Explanation: S3 is the supply depot—without this, your private world starves (updates, artifacts, logs).
resource "aws_vpc_endpoint" "vandelay_vpce_s3_gw01" {
  vpc_id            = aws_vpc.vandelay_vpc01.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.vandelay_private_rt01.id
  ]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpce-s3-gw01"
  })
}

############################################
# VPC Endpoints - SSM (Interface)
############################################

# Explanation: SSM is your Force choke—remote control without SSH, and nobody sees your keys.
resource "aws_vpc_endpoint" "vandelay_vpce_ssm01" {
  vpc_id              = aws_vpc.vandelay_vpc01.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.vandelay_private_subnets[*].id
  security_group_ids = [aws_security_group.vandelay_vpce_sg01.id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpce-ssm01"
  })
}

# Explanation: ec2messages is the messenger—SSM sessions won't work without it.
resource "aws_vpc_endpoint" "vandelay_vpce_ec2messages01" {
  vpc_id              = aws_vpc.vandelay_vpc01.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.vandelay_private_subnets[*].id
  security_group_ids = [aws_security_group.vandelay_vpce_sg01.id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpce-ec2messages01"
  })
}

# Explanation: ssmmessages is the holonet channel—Session Manager needs it to talk back.
resource "aws_vpc_endpoint" "vandelay_vpce_ssmmessages01" {
  vpc_id              = aws_vpc.vandelay_vpc01.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.vandelay_private_subnets[*].id
  security_group_ids = [aws_security_group.vandelay_vpce_sg01.id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpce-ssmmessages01"
  })
}

############################################
# VPC Endpoint - CloudWatch Logs (Interface)
############################################

# Explanation: CloudWatch Logs is the ship's black box—Vandelay wants crash data, always.
resource "aws_vpc_endpoint" "vandelay_vpce_logs01" {
  vpc_id              = aws_vpc.vandelay_vpc01.id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.vandelay_private_subnets[*].id
  security_group_ids = [aws_security_group.vandelay_vpce_sg01.id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpce-logs01"
  })
}

############################################
# VPC Endpoint - Secrets Manager (Interface)
# NOTE: This may conflict with the one in 07-compute.tf
# Remove if already defined there
############################################

# resource "aws_vpc_endpoint" "vandelay_vpce_secrets01" {
#   vpc_id              = aws_vpc.vandelay_vpc01.id
#   service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
#   vpc_endpoint_type   = "Interface"
#   private_dns_enabled = true
#
#   subnet_ids         = aws_subnet.vandelay_private_subnets[*].id
#   security_group_ids = [aws_security_group.vandelay_vpce_sg01.id]
#
#   tags = merge(local.common_tags, {
#     Name = "${local.name_prefix}-vpce-secrets01"
#   })
# }

############################################
# Optional: VPC Endpoint - KMS (Interface)
############################################

# Explanation: KMS is the encryption kyber crystal—Vandelay prefers locked doors AND locked safes.
resource "aws_vpc_endpoint" "vandelay_vpce_kms01" {
  vpc_id              = aws_vpc.vandelay_vpc01.id
  service_name        = "com.amazonaws.${var.aws_region}.kms"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.vandelay_private_subnets[*].id
  security_group_ids = [aws_security_group.vandelay_vpce_sg01.id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpce-kms01"
  })
}

############################################
# Least-Privilege IAM (BONUS A)
############################################

# Explanation: Vandelay doesn't hand out keys—this policy scopes reads to your lab paths only.
resource "aws_iam_policy" "vandelay_leastpriv_read_params01" {
  name        = "${local.name_prefix}-lp-ssm-read01"
  description = "Least-privilege read for SSM Parameter Store under /lab/db/*"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadLabDbParams"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = [
          "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.vandelay_self01.account_id}:parameter/lab/db/*"
        ]
      }
    ]
  })
}

# Explanation: Vandelay only opens *this* vault—GetSecretValue for only your secret (not the whole planet).
resource "aws_iam_policy" "vandelay_leastpriv_read_secret01" {
  name        = "${local.name_prefix}-lp-secrets-read01"
  description = "Least-privilege read for the lab DB secret"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadOnlyLabSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "${data.aws_secretsmanager_secret.vandelay_db_secret01.arn}*"
      }
    ]
  })
}

# Explanation: This lets Vandelay ship logs to CloudWatch without giving away secrets.
resource "aws_iam_policy" "vandelay_leastpriv_cwlogs01" {
  name        = "${local.name_prefix}-lp-cwlogs01"
  description = "Least-privilege CloudWatch Logs write for the app log group"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.vandelay_log_group01.arn}:*"
        ]
      }
    ]
  })
}

# Explanation: Attach the scoped policies—Vandelay loves power, but only the safe kind.
resource "aws_iam_role_policy_attachment" "vandelay_attach_lp_params01" {
  role       = aws_iam_role.vandelay_ec2_role01.name
  policy_arn = aws_iam_policy.vandelay_leastpriv_read_params01.arn
}

resource "aws_iam_role_policy_attachment" "vandelay_attach_lp_secret01" {
  role       = aws_iam_role.vandelay_ec2_role01.name
  policy_arn = aws_iam_policy.vandelay_leastpriv_read_secret01.arn
}

resource "aws_iam_role_policy_attachment" "vandelay_attach_lp_cwlogs01" {
  role       = aws_iam_role.vandelay_ec2_role01.name
  policy_arn = aws_iam_policy.vandelay_leastpriv_cwlogs01.arn
}