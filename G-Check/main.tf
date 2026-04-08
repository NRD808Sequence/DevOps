

#=============================================================================
# SSM PARAMETER STORE - Configuration Storage for Lab 1b
#=============================================================================

resource "aws_ssm_parameter" "vandelay_db_endpoint" {
  name  = "/${var.project_name}/db/endpoint"
  type  = "String"
  value = aws_db_instance.vandelay_rds01.address

  tags = {
    Name = "${var.project_name}-param-db-endpoint"
  }
}

resource "aws_ssm_parameter" "vandelay_db_port" {
  name  = "/${var.project_name}/db/port"
  type  = "String"
  value = tostring(aws_db_instance.vandelay_rds01.port)

  tags = {
    Name = "${var.project_name}-param-db-port"
  }
}

resource "aws_ssm_parameter" "vandelay_db_name" {
  name  = "/${var.project_name}/db/name"
  type  = "String"
  value = var.db_name

  tags = {
    Name = "${var.project_name}-param-db-name"
  }
}

