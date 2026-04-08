locals {
  name_prefix = var.project_name

  common_tags = {
    Lab = "ec2-rds-integration"
  }
}