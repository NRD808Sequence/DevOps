############################################
# VPC + Internet Gateway VPC, Subnets, Gateways, Routing
############################################
# Without an IGW, nothing in your VPC can reach the internet.
# Only public subnets route through this.
# Explanation: vandelay needs a hyperlane—this VPC is the Millennium Falcon’s flight corridor.

resource "aws_vpc" "vandelay_vpc01" {
  cidr_block           = var.vpc_cidr # 10.75.0.0/16
  enable_dns_support   = true         # Enables DNS resolution
  enable_dns_hostnames = true         # Enables DNS hostnames for EC2

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc01"
  })
}

# Explanation: Even Wookiees need to reach the wider galaxy—IGW is your door to the public internet.
resource "aws_internet_gateway" "vandelay_igw01" {
  vpc_id = aws_vpc.vandelay_vpc01.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}