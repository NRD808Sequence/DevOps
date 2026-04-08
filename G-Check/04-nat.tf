############################################
# NAT Gateway + EIP Allows private subnets to reach internet (outbound only)
############################################
# NAT Gateway lets private resources (like RDS) download updates,
# but prevents incoming connections from the internet.
# Explanation: vandelay wants the private base to call home—EIP gives the NAT a stable “holonet address.”

resource "aws_eip" "vandelay_nat_eip01" {
  domain = "vpc" # Allocate in VPC scope

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-eip01"
  })
}

# Explanation: NAT is vandelay’s smuggler tunnel—private subnets can reach out without being seen.
resource "aws_nat_gateway" "vandelay_nat01" {
  allocation_id = aws_eip.vandelay_nat_eip01.id
  subnet_id     = aws_subnet.vandelay_public_subnets[0].id # NAT in a public subnet

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat01"
  })

  depends_on = [aws_internet_gateway.vandelay_igw01]
}
