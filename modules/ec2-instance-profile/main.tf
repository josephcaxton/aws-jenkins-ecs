# --------
# EC2 Role
# --------
resource "aws_iam_role" "ec2_role" {
  name = "${var.customer_name}_${var.environment}_ec2_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "vpc-flow-logs.amazonaws.com",
          "ec2.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}


# ---------------
# EC2 Role Policy
# ---------------
resource "aws_iam_role_policy" "ec2_policy" {
  name = "${var.customer_name}_${var.environment}_ec2_policy"
  role = "${aws_iam_role.ec2_role.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
      {
          "Effect": "Allow",
          "Action": [
            "ecs:*",
            "elasticloadbalancing:Describe*",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ],
          "Resource": "*"
      }
  ]
}
EOF
}


# --------------------
# EC2 Instance Profile 
# --------------------
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name  = "ec2_instance_profile"
  role = "${aws_iam_role.ec2_role.name}"
}
