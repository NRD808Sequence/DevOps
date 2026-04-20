############################################
# RDS Instance (MySQL)
############################################

resource "aws_db_instance" "vandelay_rds01" {
  identifier        = "${local.name_prefix}-rds01"
  engine            = var.db_engine
  instance_class    = var.db_instance_class
  allocated_storage = 20
  db_name           = var.db_name
  username          = var.db_username
  password          = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.vandelay_rds_subnet_group01.name
  vpc_security_group_ids = [aws_security_group.vandelay_rds_sg01.id]

  publicly_accessible = false
  skip_final_snapshot = true

  # Ignore password changes - Secrets Manager rotation manages the password
  lifecycle {
    ignore_changes = [password]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds01"
  })
}

############################################
# IAM Role + Instance Profile for EC2
############################################

resource "aws_iam_role" "vandelay_ec2_role01" {
  name = "${local.name_prefix}-ec2-role01"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "vandelay_ec2_read_secret" {
  name = "${local.name_prefix}-ec2-read-secret-policy"
  role = aws_iam_role.vandelay_ec2_role01.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadSpecificSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "${data.aws_secretsmanager_secret.vandelay_db_secret01.arn}*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "vandelay_ec2_ssm_attach" {
  role       = aws_iam_role.vandelay_ec2_role01.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "vandelay_ec2_cw_attach" {
  role       = aws_iam_role.vandelay_ec2_role01.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "vandelay_instance_profile01" {
  name = "${local.name_prefix}-instance-profile01"
  role = aws_iam_role.vandelay_ec2_role01.name
}

############################################
# EC2 Instance (App Host)
############################################

resource "aws_instance" "vandelay_ec201" {
  ami                    = var.ec2_ami_id
  instance_type          = var.ec2_instance_type
  subnet_id              = aws_subnet.vandelay_public_subnets[0].id
  vpc_security_group_ids = [aws_security_group.vandelay_ec2_sg01.id]
  iam_instance_profile   = aws_iam_instance_profile.vandelay_instance_profile01.name

  user_data = file("${path.module}/user_data.sh")

  # IMDSv2 required — blocks SSRF-based credential theft (OWASP A10)
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tags = {
    Name = "${local.name_prefix}-ec201"
  }
}

############################################
# Parameter Store (SSM Parameters)
############################################

resource "aws_ssm_parameter" "vandelay_db_endpoint_param" {
  name  = "/lab/db/endpoint"
  type  = "String"
  value = aws_db_instance.vandelay_rds01.address

  tags = {
    Name = "${local.name_prefix}-param-db-endpoint"
  }
}

resource "aws_ssm_parameter" "vandelay_db_port_param" {
  name  = "/lab/db/port"
  type  = "String"
  value = tostring(aws_db_instance.vandelay_rds01.port)

  tags = {
    Name = "${local.name_prefix}-param-db-port"
  }
}

resource "aws_ssm_parameter" "vandelay_db_name_param" {
  name  = "/lab/db/name"
  type  = "String"
  value = var.db_name

  tags = {
    Name = "${local.name_prefix}-param-db-name"
  }
}

############################################
# Reference Existing Secret (Never Destroyed by Terraform)
############################################

data "aws_secretsmanager_secret" "vandelay_db_secret01" {
  name = "lab/rds/mysql"
}

data "aws_secretsmanager_secret_version" "vandelay_db_secret_version01" {
  secret_id = data.aws_secretsmanager_secret.vandelay_db_secret01.id
}

############################################
# Lambda Rotation Function
############################################

resource "aws_iam_role" "rotation_lambda_role" {
  name = "${local.name_prefix}-rotation-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "rotation_lambda_basic" {
  role       = aws_iam_role.rotation_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "rotation_lambda_vpc" {
  role       = aws_iam_role.rotation_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "rotation_lambda_policy" {
  name = "${local.name_prefix}-rotation-lambda-policy"
  role = aws_iam_role.rotation_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage"
        ]
        Resource = data.aws_secretsmanager_secret.vandelay_db_secret01.arn
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetRandomPassword"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusters"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_security_group" "rotation_lambda_sg" {
  name        = "${local.name_prefix}-rotation-lambda-sg"
  description = "Security group for secret rotation Lambda"
  vpc_id      = aws_vpc.vandelay_vpc01.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rotation-lambda-sg"
  })
}

data "aws_serverlessapplicationrepository_application" "secrets_manager_rotation" {
  application_id = "arn:aws:serverlessrepo:us-east-1:297356227824:applications/SecretsManagerRDSMySQLRotationSingleUser"
}

resource "aws_serverlessapplicationrepository_cloudformation_stack" "rotation_lambda" {
  name             = "${local.name_prefix}-mysql-rotation"
  application_id   = data.aws_serverlessapplicationrepository_application.secrets_manager_rotation.application_id
  semantic_version = data.aws_serverlessapplicationrepository_application.secrets_manager_rotation.semantic_version
  capabilities     = data.aws_serverlessapplicationrepository_application.secrets_manager_rotation.required_capabilities

  parameters = {
    endpoint            = "https://secretsmanager.${var.aws_region}.amazonaws.com"
    functionName        = "${local.name_prefix}-mysql-rotation-lambda"
    vpcSubnetIds        = join(",", aws_subnet.vandelay_private_subnets[*].id)
    vpcSecurityGroupIds = aws_security_group.rotation_lambda_sg.id
  }

  tags = local.common_tags

  # Wait for the Jenkins IAM policy to be applied before modifying the SAR stack.
  # Without this, Terraform applies both in parallel and the SAR call races the
  # IAM propagation, producing a CreateCloudFormationChangeSet AccessDeniedException.
  depends_on = [aws_iam_role_policy.vandelay_jenkins_terraform]
}

resource "aws_lambda_permission" "secrets_manager_rotation" {
  statement_id  = "AllowSecretsManagerInvocation"
  action        = "lambda:InvokeFunction"
  function_name = "${local.name_prefix}-mysql-rotation-lambda"
  principal     = "secretsmanager.amazonaws.com"

  depends_on = [aws_serverlessapplicationrepository_cloudformation_stack.rotation_lambda]
}

resource "aws_secretsmanager_secret_rotation" "vandelay_db_rotation" {
  secret_id           = data.aws_secretsmanager_secret.vandelay_db_secret01.id
  rotation_lambda_arn = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${local.name_prefix}-mysql-rotation-lambda"

  rotation_rules {
    automatically_after_days = 30
  }

  depends_on = [
    aws_serverlessapplicationrepository_cloudformation_stack.rotation_lambda,
    aws_lambda_permission.secrets_manager_rotation
  ]
}

data "aws_caller_identity" "current" {}

############################################
# VPC Endpoint for Secrets Manager
############################################

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.vandelay_vpc01.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.vandelay_private_subnets[*].id
  security_group_ids  = [aws_security_group.vpce_sg.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-secretsmanager-vpce"
  })
}

resource "aws_security_group" "vpce_sg" {
  name        = "${local.name_prefix}-vpce-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.vandelay_vpc01.id

  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    security_groups = [
      aws_security_group.rotation_lambda_sg.id,
      aws_security_group.vandelay_ec2_sg01.id,
      aws_security_group.vandelay_jenkins_sg.id
    ]
    description = "Allow HTTPS from Lambda, EC2, and Jenkins"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpce-sg"
  })
}