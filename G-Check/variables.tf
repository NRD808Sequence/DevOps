variable "aws_region" {
  description = "AWS Region for the Chewbacca fleet to patrol."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix for naming. Students should change from 'chewbacca' to their own."
  type        = string
  default     = "vandelay"
}

variable "vpc_cidr" {
  description = "VPC CIDR (use 10.x.x.x/xx as instructed)."
  type        = string
  default     = "10.75.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs (use 10.x.x.x/xx)."
  type        = list(string)
  default     = ["10.75.1.0/24", "10.75.11.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs (use 10.x.x.x/xx)."
  type        = list(string)
  default     = ["10.75.101.0/24", "10.75.128.0/24"]
}

variable "azs" {
  description = "Availability Zones list (match count with subnets)."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "ec2_ami_id" {
  description = "AMI ID for the EC2 app host."
  type        = string
  default     = "ami-0c02fb55956c7d316" # Amazon Linux 2 in us-east-1
}

variable "jenkins_ami_id" {
  description = "AMI ID for the Jenkins EC2 host. Defaults to Amazon Linux 2023."
  type        = string
  default     = "ami-02dfbd4ff395f2a1b" # Amazon Linux 2023 in us-east-1
}

variable "ec2_instance_type" {
  description = "EC2 instance size for the app."
  type        = string
  default     = "t3.micro"
}

variable "jenkins_instance_type" {
  description = "EC2 instance size for Jenkins (t3.medium recommended for 300+ plugins)."
  type        = string
  default     = "t3.medium"
}

variable "db_engine" {
  description = "RDS engine."
  type        = string
  default     = "mysql"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "labmysql"
}

variable "db_username" {
  description = "DB master username (students should use Secrets Manager in 1B/1C)."
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "DB master password — set via TF_VAR_db_password (no default)"
  type        = string
  sensitive   = true
}

variable "sns_email_endpoint" {
  description = "Email for SNS subscription (PagerDuty simulation). Set via TF_VAR_sns_email_endpoint or terraform.tfvars."
  type        = string
  default     = "gaijinmzungu@gmail.com"
}

variable "my_ip" {
  description = "Admin IP CIDR — no longer used for SG rules (Jenkins moved to ALB). Kept to avoid breaking terraform.tfvars."
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}/[0-9]{1,2}$", var.my_ip))
    error_message = "my_ip must be a valid CIDR (e.g. 203.0.113.50/32)."
  }
}

############################################
# Bonus-B Variables
############################################

variable "domain_name" {
  description = "Root domain name"
  type        = string
  default     = "keepuneat.click"
}

variable "app_subdomain" {
  description = "Subdomain for the application"
  type        = string
  default     = "app"
}

variable "alb_ingress_cidr" {
  description = "CIDR allowed to reach ALB (0.0.0.0/0 for public)"
  type        = string
  default     = "0.0.0.0/0"
}

############################################
# Bonus A & B Additional Variables
############################################

variable "waf_log_retention_days" {
  description = "Number of days to retain WAF logs in CloudWatch"
  type        = number
  default     = 30
}

variable "enable_alb_access_logs" {
  description = "Enable ALB access logging to S3"
  type        = bool
  default     = true
}

variable "alb_access_logs_prefix" {
  description = "S3 prefix for ALB access logs"
  type        = string
  default     = "alb-logs"
}

variable "alb_logs_retention_days" {
  description = "Number of days to retain ALB logs in S3"
  type        = number
  default     = 90
}

variable "enable_private_ec2" {
  description = "Move EC2 to private subnet (requires VPC endpoints)"
  type        = bool
  default     = false # Set to true after VPC endpoints are deployed
}

