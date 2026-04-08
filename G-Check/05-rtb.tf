############################################
# Routing (Public + Private Route Tables)
############################################

# Explanation: Public route table = “open lanes” to the galaxy via IGW.
resource "aws_route_table" "vandelay_public_rt01" {
  vpc_id = aws_vpc.vandelay_vpc01.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-rt01"
  })
}

# Explanation: This route is the Kessel Run—0.0.0.0/0 goes out the IGW.
resource "aws_route" "vandelay_public_default_route" {
  route_table_id         = aws_route_table.vandelay_public_rt01.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.vandelay_igw01.id
}

# Explanation: Attach public subnets to the “public lanes.”
resource "aws_route_table_association" "vandelay_public_rta" {
  count          = length(aws_subnet.vandelay_public_subnets)
  subnet_id      = aws_subnet.vandelay_public_subnets[count.index].id
  route_table_id = aws_route_table.vandelay_public_rt01.id
}

# Explanation: Private route table = “stay hidden, but still ship supplies.”
resource "aws_route_table" "vandelay_private_rt01" {
  vpc_id = aws_vpc.vandelay_vpc01.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-rt01"
  })
}

# Explanation: Private subnets route outbound internet via NAT (vandelay-approved stealth).
resource "aws_route" "vandelay_private_default_route" {
  route_table_id         = aws_route_table.vandelay_private_rt01.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.vandelay_nat01.id
}

# Explanation: Attach private subnets to the “stealth lanes.”
resource "aws_route_table_association" "vandelay_private_rta" {
  count          = length(aws_subnet.vandelay_private_subnets)
  subnet_id      = aws_subnet.vandelay_private_subnets[count.index].id
  route_table_id = aws_route_table.vandelay_private_rt01.id
}

