#=============================================================================
# OUTPUTS.TF - Vandelay Industries Cloud Infrastructure
#=============================================================================

#-----------------------------------------------------------------------------
# NETWORK OUTPUTS
#-----------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.vandelay_vpc01.id
}

output "public_subnet_ids" {
  description = "IDs of public subnets (where EC2 lives)"
  value       = aws_subnet.vandelay_public_subnets[*].id
}

output "private_subnet_ids" {
  description = "IDs of private subnets (where RDS lives)"
  value       = aws_subnet.vandelay_private_subnets[*].id
}

#-----------------------------------------------------------------------------
# EC2 OUTPUTS
#-----------------------------------------------------------------------------

output "ec2_instance_id" {
  description = "ID of the EC2 instance - use in gate scripts"
  value       = aws_instance.vandelay_ec201.id
}

output "ec2_public_ip" {
  description = "Public IP of EC2 - use this in your browser!"
  value       = aws_instance.vandelay_ec201.public_ip
}

output "ec2_public_dns" {
  description = "Public DNS of EC2 - alternative to IP"
  value       = aws_instance.vandelay_ec201.public_dns
}

#-----------------------------------------------------------------------------
# SECURITY GROUP OUTPUTS
#-----------------------------------------------------------------------------

output "ec2_security_group_id" {
  description = "ID of EC2 security group"
  value       = aws_security_group.vandelay_ec2_sg01.id
}

output "rds_security_group_id" {
  description = "ID of RDS security group"
  value       = aws_security_group.vandelay_rds_sg01.id
}

#-----------------------------------------------------------------------------
# RDS OUTPUTS
#-----------------------------------------------------------------------------

output "rds_endpoint" {
  description = "RDS endpoint address"
  value       = aws_db_instance.vandelay_rds01.address
}

output "rds_port" {
  description = "RDS port number"
  value       = aws_db_instance.vandelay_rds01.port
}

output "rds_identifier" {
  description = "RDS instance identifier"
  value       = aws_db_instance.vandelay_rds01.identifier
}

#-----------------------------------------------------------------------------
# SECRETS MANAGER OUTPUTS
#-----------------------------------------------------------------------------

output "secret_name" {
  description = "Name of the Secrets Manager secret"
  value       = data.aws_secretsmanager_secret.vandelay_db_secret01.name
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret"
  value       = data.aws_secretsmanager_secret.vandelay_db_secret01.arn
}

#-----------------------------------------------------------------------------
# IAM OUTPUTS
#-----------------------------------------------------------------------------

output "iam_role_name" {
  description = "Name of the IAM role attached to EC2"
  value       = aws_iam_role.vandelay_ec2_role01.name
}

output "instance_profile_name" {
  description = "Name of the instance profile"
  value       = aws_iam_instance_profile.vandelay_instance_profile01.name
}

#-----------------------------------------------------------------------------
# MONITORING OUTPUTS
#-----------------------------------------------------------------------------

output "sns_topic_arn" {
  description = "ARN of SNS topic for alerts"
  value       = aws_sns_topic.vandelay_sns_topic01.arn
}

output "log_group_name" {
  description = "Name of CloudWatch log group"
  value       = aws_cloudwatch_log_group.vandelay_log_group01.name
}

#-----------------------------------------------------------------------------
# HELPFUL COMMANDS OUTPUT
#-----------------------------------------------------------------------------

output "app_urls" {
  description = "URLs to test the application"
  value = {
    home = "http://${aws_instance.vandelay_ec201.public_ip}/"
    init = "http://${aws_instance.vandelay_ec201.public_ip}/init"
    add  = "http://${aws_instance.vandelay_ec201.public_ip}/add?note=hello_vandelay"
    list = "http://${aws_instance.vandelay_ec201.public_ip}/list"
  }
}

output "gate_script_variables" {
  description = "Variables for the gate validation scripts"
  value = {
    REGION      = var.aws_region
    INSTANCE_ID = aws_instance.vandelay_ec201.id
    SECRET_ID   = data.aws_secretsmanager_secret.vandelay_db_secret01.name
    DB_ID       = aws_db_instance.vandelay_rds01.identifier
  }
}

#-----------------------------------------------------------------------------
# SECRET ROTATION OUTPUTS
#-----------------------------------------------------------------------------

output "rotation_lambda_name" {
  description = "Name of the secret rotation Lambda function"
  value       = "${local.name_prefix}-mysql-rotation-lambda"
}

output "secret_rotation_enabled" {
  description = "Whether secret rotation is enabled"
  value       = true
}


#-----------------------------------------------------------------------------
# BONUS OUTPUTS
#-----------------------------------------------------------------------------

# Explanation: Outputs are your mission report—what got built and where to find it.
output "vandelay_vpc_id" {
  description = "ID of the Vandelay VPC"
  value       = aws_vpc.vandelay_vpc01.id
}

output "vandelay_public_subnet_ids" {
  description = "IDs of Vandelay public subnets"
  value       = aws_subnet.vandelay_public_subnets[*].id
}

output "vandelay_private_subnet_ids" {
  description = "IDs of Vandelay private subnets"
  value       = aws_subnet.vandelay_private_subnets[*].id
}

output "vandelay_ec2_instance_id" {
  description = "ID of the Vandelay EC2 instance"
  value       = aws_instance.vandelay_ec201.id
}

output "vandelay_rds_endpoint" {
  description = "Endpoint of the Vandelay RDS instance"
  value       = aws_db_instance.vandelay_rds01.address
}

output "vandelay_sns_topic_arn" {
  description = "ARN of the Vandelay SNS topic"
  value       = aws_sns_topic.vandelay_sns_topic01.arn
}

output "vandelay_log_group_name" {
  description = "Name of the Vandelay CloudWatch log group"
  value       = aws_cloudwatch_log_group.vandelay_log_group01.name
}

#-----------------------------------------------------------------------------
# JENKINS OUTPUTS
#-----------------------------------------------------------------------------

output "jenkins_instance_id" {
  description = "ID of the Jenkins EC2 instance"
  value       = aws_instance.vandelay_jenkins.id
}

output "jenkins_public_ip" {
  description = "Public IP of Jenkins EC2"
  value       = aws_instance.vandelay_jenkins.public_ip
}

output "jenkins_url" {
  description = "HTTPS URL to access Jenkins UI via ALB"
  value       = "https://jenkins.${var.domain_name}"
}

output "jenkins_alb_dns" {
  description = "Raw ALB DNS name for Jenkins"
  value       = aws_lb.vandelay_jenkins_alb.dns_name
}

output "jenkins_initial_password_cmd" {
  description = "SSM command to retrieve the Jenkins initial admin password"
  value       = "aws ssm start-session --target ${aws_instance.vandelay_jenkins.id} --region ${var.aws_region} --document-name AWS-StartInteractiveCommand --parameters 'command=sudo cat /var/lib/jenkins/secrets/initialAdminPassword'"
}

# Bonus: Private EC2 instance (if using bonus file)
output "vandelay_ec2_private_instance_id" {
  description = "ID of the Vandelay private EC2 instance (Bonus A)"
  value       = aws_instance.vandelay_ec201_private_bonus.id
}
