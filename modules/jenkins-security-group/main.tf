# ----------------------
# Jenkins Security Group
# ----------------------
resource "aws_security_group" "this" {
  name        = "${var.customer_name}_${var.environment}_jenkins_sg"
  description = "Jenkins Instance Security Group"
  vpc_id      = "${var.vpc_id}"

  # Bastion SSH Ingress Rule
  ingress {
    from_port       = "${var.ssh_port}"
    to_port         = "${var.ssh_port}"
    protocol        = "tcp"
    security_groups = ["${var.bastion_security_group}"]
  }

  # Jenkins WEB Ingress Rule
  ingress {
    from_port   = "${var.jenkins_web_port}"
    to_port     = "${var.jenkins_web_port}"
    protocol    = "tcp"
    cidr_blocks = ["${var.vpc_cidr_block}"]
  }

  # Jenkins JNLP Ingress Rule
  ingress {
    from_port   = "${var.jenkins_jnlp_port}"
    to_port     = "${var.jenkins_jnlp_port}"
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
    Name        = "${var.customer_name}_${var.environment}_jenkins_sg"
    Environment = "S{var.environment}"
    Terraform   = "true"
  }
}
