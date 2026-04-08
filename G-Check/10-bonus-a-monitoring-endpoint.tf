############################################
# CloudWatch Monitoring VPC Endpoint
# Enables EC2 to push metrics without internet
############################################

resource "aws_vpc_endpoint" "vandelay_vpce_monitoring" {
  vpc_id              = aws_vpc.vandelay_vpc01.id
  service_name        = "com.amazonaws.${var.aws_region}.monitoring"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.vandelay_private_subnets[*].id
  security_group_ids = [aws_security_group.vpce_sg.id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpce-monitoring"
  })
}

output "vandelay_vpce_monitoring_id" {
  description = "CloudWatch Monitoring Interface Endpoint ID"
  value       = aws_vpc_endpoint.vandelay_vpce_monitoring.id
}
