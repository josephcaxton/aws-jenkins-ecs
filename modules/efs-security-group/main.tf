# --------------------------
# Jenkins ELB Security Group
# --------------------------
resource "aws_security_group" "this" {
  name        = "${var.customer_name}_${var.environment}_efs_sg"
  description = "EFS Security Group"
  vpc_id      = "${var.vpc_id}"

  # Default EFS Ingress Rule
  ingress {
    from_port   = "${var.efs_port}"
    to_port     = "${var.efs_port}"
    protocol    = "tcp"
    cidr_blocks = ["${var.vpc_cidr_block}"]
  }

  # Default Egress Rule
  egress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    ignore_changes = ["name"]
  }

  tags {
    Name        = "${var.customer_name}_${var.environment}_efs_sg"
    Environment = "S{var.environment}"
    Terraform   = "true"
  }
}
