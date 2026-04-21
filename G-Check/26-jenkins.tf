############################################
# Jenkins Server
############################################

# Security Group for Jenkins EC2
resource "aws_security_group" "vandelay_jenkins_sg" {
  name        = "${local.name_prefix}-jenkins-sg"
  description = "Security group for Jenkins server"
  vpc_id      = aws_vpc.vandelay_vpc01.id

  # Port 8080 ingress is managed by aws_security_group_rule.vandelay_jenkins_from_alb
  # in 27-jenkins-alb.tf — ALB SG only, no direct internet access.

  # SSH removed — use AWS Systems Manager Session Manager (SSM) instead.
  # AmazonSSMManagedInstanceCore is attached to vandelay-jenkins-role.
  # Connect via: aws ssm start-session --target <instance-id>

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-jenkins-sg"
  })
}

# IAM Role for Jenkins EC2
resource "aws_iam_role" "vandelay_jenkins_role" {
  name = "${local.name_prefix}-jenkins-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

# SSM access so you can use Session Manager instead of raw SSH
resource "aws_iam_role_policy_attachment" "vandelay_jenkins_ssm" {
  role       = aws_iam_role.vandelay_jenkins_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch agent (optional but useful for Jenkins log shipping)
resource "aws_iam_role_policy_attachment" "vandelay_jenkins_cw" {
  role       = aws_iam_role.vandelay_jenkins_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "vandelay_jenkins_profile" {
  name = "${local.name_prefix}-jenkins-profile"
  role = aws_iam_role.vandelay_jenkins_role.name
}

# Terraform deploy permissions — lets Jenkins run terraform init/plan/apply
# against the lab-2 stack. Scoped to the S3 state bucket + full infra actions.
resource "aws_iam_role_policy" "vandelay_jenkins_terraform" {
  name = "VandelayTerraformDeployPolicy"
  role = aws_iam_role.vandelay_jenkins_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformStateS3"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketVersioning",
          "s3:GetEncryptionConfiguration"
        ]
        Resource = [
          "arn:aws:s3:::class7-armagaggeon-tf-bucket",
          "arn:aws:s3:::class7-armagaggeon-tf-bucket/*"
        ]
      },
      {
        Sid    = "TerraformInfra"
        Effect = "Allow"
        Action = [
          "ec2:*", "elasticloadbalancing:*", "rds:*",
          "secretsmanager:*", "cloudfront:*", "wafv2:*",
          "route53:*", "route53domains:*", "cloudwatch:*",
          "logs:*", "iam:*", "lambda:*", "s3:*", "sns:*",
          "sqs:*", "acm:*", "dynamodb:*", "autoscaling:*",
          "ssm:*", "kms:*", "events:*", "firehose:*",
          "cloudtrail:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "ServerlessApplicationRepository"
        Effect = "Allow"
        Action = [
          "serverlessrepo:GetApplication",
          "serverlessrepo:CreateCloudFormationTemplate",
          "serverlessrepo:GetCloudFormationTemplate",
          "serverlessrepo:ListApplicationVersions",
          "serverlessrepo:CreateCloudFormationChangeSet",
          "cloudformation:CreateChangeSet",
          "cloudformation:DescribeChangeSet",
          "cloudformation:ExecuteChangeSet",
          "cloudformation:DescribeStacks",
          "cloudformation:DescribeStackEvents",
          "cloudformation:GetTemplate",
          "cloudformation:ListStacks",
          "cloudformation:CreateStack",
          "cloudformation:UpdateStack",
          "cloudformation:DeleteStack",
          "cloudformation:ValidateTemplate"
        ]
        Resource = "*"
      }
    ]
  })
}

# Jenkins EC2 Instance
resource "aws_instance" "vandelay_jenkins" {
  ami                    = var.jenkins_ami_id
  instance_type          = var.jenkins_instance_type
  subnet_id              = aws_subnet.vandelay_public_subnets[0].id
  vpc_security_group_ids = [aws_security_group.vandelay_jenkins_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.vandelay_jenkins_profile.name

  user_data = file("${path.module}/jenkins_user_data.sh")

  # IMDSv2 required — blocks SSRF-based credential theft (OWASP A10)
  # Jenkins IAM role has iam:* — IMDSv1 would be full account takeover via SSRF
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  # Prevent Terraform from replacing the running Jenkins instance when
  # user_data or AMI changes. Jenkins bootstraps once on first launch —
  # replacing it mid-pipeline would kill the running build.
  # Apply user_data changes manually via SSM, or destroy+recreate deliberately.
  lifecycle {
    ignore_changes = [user_data, ami]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-jenkins"
  })
}

############################################
# Persistent EBS Volume for Jenkins Home
############################################

# This volume survives EC2 teardown — plugins, jobs, and config are preserved.
# IMPORTANT: prevent_destroy = true means `terraform destroy` will error unless
# you remove this block first. This is intentional to protect your Jenkins data.
resource "aws_ebs_volume" "vandelay_jenkins_data" {
  availability_zone = var.azs[0]
  size              = 20
  type              = "gp3"

  lifecycle {
    prevent_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-jenkins-data"
  })
}

resource "aws_volume_attachment" "vandelay_jenkins_data" {
  device_name  = "/dev/xvdf"
  volume_id    = aws_ebs_volume.vandelay_jenkins_data.id
  instance_id  = aws_instance.vandelay_jenkins.id
  force_detach = true
}
