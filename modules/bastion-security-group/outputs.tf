# --------------
# Module Outputs
# --------------
output "bastion_security_group_id" {
  value = "${aws_security_group.this.id}"
}
