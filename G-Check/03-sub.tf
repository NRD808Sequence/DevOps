############################################
# Subnets (Public + Private)
############################################
#-----------------------------------------------------------------------------
# PUBLIC SUBNETS - Where EC2 lives (internet accessible)
#-----------------------------------------------------------------------------
# Explanation: Public subnets are like docking bays—ships can land directly from space (internet).

resource "aws_subnet" "vandelay_public_subnets" {
  count                   = length(var.public_subnet_cidrs) # Creates 2 subnets
  vpc_id                  = aws_vpc.vandelay_vpc01.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-subnet-${count.index + 1}"
    Tier = "public"
  })
}

#-----------------------------------------------------------------------------
# PRIVATE SUBNETS - Where RDS hides (no direct internet access)
#-----------------------------------------------------------------------------
# Private subnets have NO route to the Internet Gateway.
# Resources here cannot be reached from the internet directly.
# Explanation: Private subnets are the hidden Rebel base—no direct access from the internet.

resource "aws_subnet" "vandelay_private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.vandelay_vpc01.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-subnet-${count.index + 1}"
    Tier = "private"
  })
}