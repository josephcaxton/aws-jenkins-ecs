# --------------
# Module Outputs
# --------------
output "ec2_role_arn" {
  value = "${aws_iam_role.ec2_role.arn}"
}

output "ec2_instance_profile_arn" {
  value = "${aws_iam_instance_profile.ec2_instance_profile.arn}"
}

output "ec2_instance_profile_name" {
  value = "${aws_iam_instance_profile.ec2_instance_profile.name}"
}
