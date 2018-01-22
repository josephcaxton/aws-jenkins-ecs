# --------------------------
# Jenkins ELB Security Group
# --------------------------
resource "aws_security_group" "this" {
  name        = "${var.customer_name}_${var.environment}_jenkins_elb_sg"
  description = "Jenkins ELB Instance Security Group"
  vpc_id      = "${var.vpc_id}"

  # Jenkins EXT WEB Ingress Rule
  ingress {
    from_port   = "${var.jenkins_ext_web_port}"
    to_port     = "${var.jenkins_ext_web_port}"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Jenkins EXT SSL Ingress Rule
  ingress {
    from_port   = "${var.jenkins_ext_ssl_port}"
    to_port     = "${var.jenkins_ext_ssl_port}"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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
    Name        = "${var.customer_name}_${var.environment}_jenkins_elb_sg"
    Environment = "S{var.environment}"
    Terraform   = "true"
  }
}
