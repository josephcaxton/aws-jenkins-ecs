# ------------
# AWS Provider
# ------------
provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "${var.region}"
}


# --------
# Key Pair
# --------
module "key_pair" {
  source = "git::https://github.com/brentwg/terraform-aws-key-pair.git?ref=1.0"

  key_pair_name   = "${var.key_pair_name}"
  public_key_path = "${var.public_key_path}"
}


# --------------------------------
# Lookup Region Availability Zones
# --------------------------------
data "aws_availability_zones" "available" {}


# ------------------------------
# Lookup Domain Zone Information
# ------------------------------
data "aws_route53_zone" "my_domain" {
  name = "${var.domain_name}"
}


# ---------------------------------
# Lookup Domain SSl Certificate ARN
# ---------------------------------
data "aws_acm_certificate" "this" {
  domain   = "${var.domain_name}"
  statuses = ["ISSUED"]
}


# ---
# VPC
# ---
module "vpc" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=v1.5.1"

  name                = "${var.vpc_name}"
  cidr                = "${var.vpc_cidr}"
  azs                 = "${data.aws_availability_zones.available.names}"
  private_subnets     = "${var.vpc_private_subnets}"
  public_subnets      = "${var.vpc_public_subnets}"

  enable_dns_hostnames = "${var.vpc_enable_dns_hostnames}"
  enable_dns_support   = "${var.vpc_enable_dns_support}"

  enable_nat_gateway           = "${var.vpc_enable_nat_gateway}"
  enable_s3_endpoint           = "${var.vpc_enable_s3_endpoint}"
  enable_dynamodb_endpoint     = "${var.vpc_enable_dynamodb_endpoint}"

  tags = {
    Name        = "${var.vpc_name}"
    Environment = "${var.environment}"
    Terraform   = "true"
  }

  private_subnet_tags = {
    SubnetType = "private"
  }

  public_subnet_tags = {
    SubnetType = "public"
  }
}


# ----------------------
# Bastion Security Group
# ----------------------
module "bastion_security_group" {
  source = "../modules/bastion-security-group"

  customer_name         = "${var.customer_name}"
  environment           = "${var.environment}"
  vpc_id                = "${module.vpc.vpc_id}"
  vpc_cidr_block        = "${module.vpc.vpc_cidr_block}"
  ssh_port              = "${var.bastion_ssh_port}"
  external_subnet_range = "${var.bastion_external_subnet_range}"
}


# -------
# Bastion
# -------
module "bastion" {
  source = "git::https://github.com/brentwg/terraform-aws-bastion.git?ref=1.0"

  customer_name       = "${var.customer_name}"
  environment         = "${var.environment}"

  # Route53
  bastion_zone_id     = "${data.aws_route53_zone.my_domain.zone_id}"
  bastion_domain_name = "bastion.${var.domain_name}"
  bastion_zone_ttl    = "${var.bastion_zone_ttl}"

  # Launch config
  bastion_region        = "${var.region}"      
  bastion_image_id      = "${var.bastion_image_id}"
  bastion_instance_type = "${var.bastion_instance_type}"
  bastion_key_name      = "${var.key_pair_name}"

  bastion_security_groups   = [
    "${module.bastion_security_group.bastion_security_group_id}"
  ]
  
  bastion_ebs_optimized     = "${var.bastion_ebs_optimized}"
  bastion_enable_monitoring = "${var.bastion_enable_monitoring}"
  bastion_volume_type       = "${var.bastion_volume_type}"
  bastion_volume_size       = "${var.bastion_volume_size}"

  # ASG
  bastion_max_size         = "${var.bastion_max_size}"
  bastion_min_size         = "${var.bastion_min_size}"
  bastion_desired_capacity = "${var.bastion_desired_capacity}"

  bastion_asg_subnets      = ["${module.vpc.public_subnets}"]
}


# ----------------------
# IAM - ECS Service Role
# ----------------------

/*
  This should be it's own module. But I need to reference a resource in order
  to prevent a potential race condition during ECS service deletion. See this
  NOTE:

    To prevent a race condition during service deletion, make sure to set 
    depends_on to the related aws_iam_role_policy; otherwise, the policy may be 
    destroyed too soon and the ECS service will then get stuck in the DRAINING 
    state.

  Original module preserved here for posterity.

  module "ecs_service_role" {
    source = "../modules/ecs-service-role"

    customer_name            = "${var.customer_name}"
    environment              = "${var.environment}"
  }
*/

# ----------------
# ECS Service Role
# ----------------
resource "aws_iam_role" "ecs_service_role" {
  name = "${var.customer_name}_${var.environment}_ecs_service_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "ecs.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# -----------------------
# ECS Service Role Policy
# -----------------------
resource "aws_iam_role_policy" "ecs_service_policy" {
  name = "${var.customer_name}_${var.environment}_s3_access_policy"
  role = "${aws_iam_role.ecs_service_role.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
      {
          "Effect": "Allow",
          "Action": [
            "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
            "elasticloadbalancing:DeregisterTargets",
            "elasticloadbalancing:Describe*",
            "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
            "elasticloadbalancing:RegisterTargets",
            "ec2:Describe*",
            "ec2:AuthorizeSecurityGroupIngress"
          ],      
          "Resource": "*"
      }
  ]
}
EOF
}


# --------------------------
# IAM - EC2 Instance Profile
# --------------------------
module "ec2_instance_profile" {
  source = "../modules/ec2-instance-profile"

  customer_name            = "${var.customer_name}"
  environment              = "${var.environment}"
}


# ----------------------
# Jenkins Security Group
# ----------------------
module "jenkins_security_group" {
  source = "../modules/jenkins-security-group"

  customer_name          = "${var.customer_name}"
  environment            = "${var.environment}"
  vpc_id                 = "${module.vpc.vpc_id}"
  vpc_cidr_block         = "${module.vpc.vpc_cidr_block}"
  ssh_port               = "${var.bastion_ssh_port}"
  jenkins_web_port       = "${var.jenkins_web_port}"
  jenkins_jnlp_port      = "${var.jenkins_jnlp_port}"
  bastion_security_group = "${module.bastion_security_group.bastion_security_group_id}"
}


# --------------------------
# Jenkins ELB Security Group
# --------------------------
module "jenkins_elb_security_group" {
  source = "../modules/jenkins-elb-security-group"

  customer_name         = "${var.customer_name}"
  environment           = "${var.environment}"
  vpc_id                = "${module.vpc.vpc_id}"
  jenkins_ext_web_port  = "${var.jenkins_ext_web_port}"
  jenkins_ext_ssl_port  = "${var.jenkins_ext_ssl_port}"
}


# ------------------
# EFS Security Group
# ------------------
module "efs_security_group" {
  source = "../modules/efs-security-group"

  customer_name         = "${var.customer_name}"
  environment           = "${var.environment}"
  vpc_id                = "${module.vpc.vpc_id}"
  vpc_cidr_block        = "${module.vpc.vpc_cidr_block}"
  efs_port              = "${var.efs_port}"
}


# ---
# EFS
# ---
module "efs" {
  source = "git::https://github.com/brentwg/terraform-aws-efs.git?ref=1.0.1"

  customer_name         = "${var.customer_name}"
  environment           = "${var.environment}"
  vpc_id                = "${module.vpc.vpc_id}"
  subnet_ids            = "${module.vpc.private_subnets}"
  subnet_count          = "${length(var.vpc_private_subnets)}"
  security_groups       = ["${module.efs_security_group.efs_security_group_id}"]
}


# -----------
# Jenkins ELB
# -----------
module "jenkins_elb" {
  source = "../modules/jenkins-elb"

  customer_name       = "${var.customer_name}"
  environment         = "${var.environment}"
  elb_subnets         = ["${module.vpc.public_subnets}"]
  elb_security_groups = ["${module.jenkins_elb_security_group.jenkins_elb_security_group_id}"]
  int_web_port        = "${var.jenkins_web_port}"
  ext_web_port        = "${var.jenkins_ext_web_port}"
  ext_ssl_port        = "${var.jenkins_ext_ssl_port}"
  ssl_certificate_id  = "${data.aws_acm_certificate.this.arn}"
  
  elb_cookie_expiration_period = "${var.jenkins_elb_cookie_expiration_period}"
}


# --------------------------------
# Jenkins ELB Route53 Alias Record
# --------------------------------
resource "aws_route53_record" "jenkins_brentwg_com" {
  zone_id = "${data.aws_route53_zone.my_domain.zone_id}"
  name    = "jenkins.${var.domain_name}"
  type    = "A"

  alias {
    name                   = "${module.jenkins_elb.jenkins_elb_dns_name}"
    zone_id                = "${module.jenkins_elb.elb_zone_id}"
    evaluate_target_health = true
  }
}


/*
  NOTE: All of the ECS resources should be in their own module. But I require
  a 'depends_on' (See Notes from 'IAM - ECS Service Role' above), so here we 
  are.
*/


# -------------------
# Jenkins ECS Cluster
# -------------------
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "${var.ecs_cluster_name}"
}


# ------------------------------
# Jenkins Master Task Definition
# ------------------------------
resource "aws_ecs_task_definition" "ecs_task_definition" {
  family       = "${var.ecs_task_family}"
  network_mode = "${var.ecs_task_network_mode}"
  
  volume {
    name      = "${var.ecs_task_volume_name}"
    host_path = "${var.ecs_task_volume_host_path}"
  }

  container_definitions = <<EOF
[
  {
    "name": "${var.ecs_task_family}",
    "image": "${var.ecs_task_image}",
    "mountPoints": [
      {
        "sourceVolume": "${var.ecs_task_volume_name}",
        "containerPath": "${var.ecs_task_container_path}"
      }
    ],
    "essential": true,
    "cpu": 1024,
    "memory": 992,
    "portMappings": [
      {
        "hostPort": 8080,
        "containerPort": 8080,
        "protocol": "tcp"
      },
      {
        "hostPort": 50000,
        "containerPort": 50000,
        "protocol": "tcp"
      }
    ]
  }
]
EOF
}


# -------------------
# Jenkins ECS Service
# -------------------
resource "aws_ecs_service" "ecs_service" {
  name            = "${var.ecs_cluster_name}"
  cluster         = "${aws_ecs_cluster.ecs_cluster.id}"
  task_definition = "${aws_ecs_task_definition.ecs_task_definition.arn}"
  desired_count   = "1"
  iam_role        = "${aws_iam_role.ecs_service_role.arn}"
  depends_on      = ["aws_iam_role_policy.ecs_service_policy"]

  load_balancer {
    elb_name = "${module.jenkins_elb.jenkins_elb_name}"
    container_name = "${var.ecs_task_family}"
    container_port = "${var.jenkins_web_port}"
  }
}


# ------------
# Auto Scaling
# ------------
data "template_file" "user_data_jenkins_ecs" {
  template = "${file("user_data_jenkins_ecs.sh")}"

  vars {
    ecs_cluster_name     = "${var.ecs_cluster_name}"
    efs_mountpoint       = "${var.ecs_user_data_efs_mountpoint}"
    aws_region           = "${var.region}"
    efs_filesystem_id    = "${module.efs.efs_filesystem_id}"
    efs_mountpoint_owner = "${var.ecs_user_data_efs_owner}"
  }
}


module "asg" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-autoscaling.git?ref=v2.0.0"

  name = "jenkins-asg_instance"

  # Launch Configuration
  lc_name              = "${var.customer_name}-${var.environment}_ecs_launch_configuration"
  image_id             = "${var.ecs_lc_image_id}"
  instance_type        = "${var.ecs_lc_instance_type}"
  iam_instance_profile = "${module.ec2_instance_profile.ec2_instance_profile_arn}"
  key_name             = "${var.key_pair_name}"
  
  load_balancers = ["${module.jenkins_elb.jenkins_elb_id}"]

  security_groups = ["${module.jenkins_security_group.jenkins_security_group_id}"]
  
  associate_public_ip_address = "false"

  user_data = "${data.template_file.user_data_jenkins_ecs.rendered}"

  ebs_block_device = [
    {
      device_name           = "${var.ecs_lc_data_block_device_name}"
      volume_type           = "${var.ecs_lc_data_block_device_type}"
      volume_size           = "${var.ecs_lc_data_block_device_size}"
      delete_on_termination = true
    },
  ]

  root_block_device = [
    {
      volume_type = "${var.ecs_lc_root_device_type}"
      volume_size = "${var.ecs_lc_root_device_size}"
    },
  ]

# Auto scaling group
  asg_name                  = "${var.customer_name}_${var.environment}_asg"
  vpc_zone_identifier       = ["${module.vpc.private_subnets}"]
  health_check_type         = "${var.ecs_asg_health_check_type}"
  min_size                  = "${var.ecs_asg_min_size}"
  max_size                  = "${var.ecs_asg_max_size}"
  desired_capacity          = "${var.ecs_asg_desired_capacity}"
  wait_for_capacity_timeout = "${var.ecs_asg_wait_for_capacity_timeout}"

  tags = [
    {
      key                 = "Name"
      value               = "${var.customer_name}_${var.environment}_asg"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = "${var.environment}"
      propagate_at_launch = true
    },
    {
      key                 = "Terraform"
      value               = "true"
      propagate_at_launch = true
    },
  ]
}


# -------------------------------
# Jenkins Cluster Scale Up Policy
# -------------------------------
resource "aws_autoscaling_policy" "jenkins_scale_up_policy" {
  name                      = "${var.customer_name}_${var.environment}_jenkins_scale_up_policy"
  adjustment_type           = "${var.scale_up_adjustment_type}"
  autoscaling_group_name    = "${module.asg.this_autoscaling_group_name}"
  estimated_instance_warmup = "${var.scale_up_estimated_instance_warmup}"
  metric_aggregation_type   = "${var.scale_up_metric_aggregation_type}"
  policy_type               = "${var.scale_up_policy_type}"

  step_adjustment {
    metric_interval_lower_bound = "${var.scale_up_metric_interval_lower_bound}"
    scaling_adjustment          = "${var.scale_up_scaling_adjustment}"
  }
}


# ------------------------------
# Jenkins Cluster Scale Up Alarm
# ------------------------------
module "jenkins_scale_up_alarm" {
  source = "git::https://github.com/brentwg/terraform-aws-cloudwatch-alarms.git?ref=1.0"

  alarm_name        = "${var.customer_name}_${var.environment}_jenkins_scale_up_alarm"
  alarm_description = "CPU utilization peaked at 70% during the last minute"
  alarm_actions     = ["${aws_autoscaling_policy.jenkins_scale_up_policy.arn}"]

  dimensions = {
    ClusterName = "${var.ecs_cluster_name}"
  }

  metric_name         = "${var.scale_up_alarm_metric_name}"
  namespace           = "${var.scale_up_alarm_namespace}"
  comparison_operator = "${var.scale_up_alarm_comparison_operator}"
  statistic           = "${var.scale_up_alarm_statistic}"
  threshold           = "${var.scale_up_alarm_threshold}"
  period              = "${var.scale_up_alarm_period}"
  evaluation_periods  = "${var.scale_up_alarm_evaluation_periods}"
  treat_missing_data  = "${var.scale_up_alarm_treat_missing_data}"
}


# ---------------------------------
# Jenkins Cluster Scale Down Policy
# ---------------------------------
resource "aws_autoscaling_policy" "jenkins_scale_down_policy" {
  name                      = "${var.customer_name}_${var.environment}_jenkins_scale_down_policy"
  adjustment_type           = "${var.scale_down_adjustment_type}"
  autoscaling_group_name    = "${module.asg.this_autoscaling_group_name}"
  cooldown                  = "${var.scale_down_cooldown}"
  scaling_adjustment        = "${var.scale_down_scaling_adjustment}"
}


# --------------------------------
# Jenkins Cluster Scale Down Alarm
# --------------------------------
module "jenkins_scale_down_alarm" {
  source = "git::https://github.com/brentwg/terraform-aws-cloudwatch-alarms.git?ref=1.0"

  alarm_name        = "${var.customer_name}_${var.environment}_jenkins_scale_down_alarm"
  alarm_description = "CPU utilization is under 50% for the last 10 min..."
  alarm_actions     = ["${aws_autoscaling_policy.jenkins_scale_down_policy.arn}"]

  dimensions = {
    ClusterName = "${var.ecs_cluster_name}"
  }

  metric_name         = "${var.scale_down_alarm_metric_name}"
  namespace           = "${var.scale_down_alarm_namespace}"
  comparison_operator = "${var.scale_down_alarm_comparison_operator}"
  statistic           = "${var.scale_down_alarm_statistic}"
  threshold           = "${var.scale_down_alarm_threshold}"
  period              = "${var.scale_down_alarm_period}"
  evaluation_periods  = "${var.scale_down_alarm_evaluation_periods}"
  treat_missing_data  = "${var.scale_down_alarm_treat_missing_data}"
}
