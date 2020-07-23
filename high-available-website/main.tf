provider "aws" {
  region = var.region
}

data "aws_availability_zones" "az" {}

data "aws_elb_service_account" "main" {}

#----------------------------------------------------------------------------
# IAM Roles and Policies
#----------------------------------------------------------------------------
resource "aws_iam_role" "vpc-fl-role" {
  name = "vpc_fl_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "vpc-flow-logs.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "vpc-fl-policy" {
  name = "vpc_fl_policy"
  role = aws_iam_role.vpc-fl-role.id


  policy = <<EOF
{
  "Statement": [
      {
          "Action": [
              "logs:CreateLogGroup",
              "logs:CreateLogStream",
              "logs:DescribeLogGroups",
              "logs:DescribeLogStreams",
              "logs:PutLogEvents"
          ],
          "Effect": "Allow",
          "Resource": "*"
      }
  ]
}
  EOF
}
#----------------------------------------------------------------------------
# Network
#----------------------------------------------------------------------------
resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_default_route_table" "route-table" {
  default_route_table_id = aws_vpc.vpc.default_route_table_id  

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }  
}

resource "aws_subnet" "public-subnets" {
  vpc_id = aws_vpc.vpc.id
  cidr_block = "10.0.${0+count.index}.0/24"
  map_public_ip_on_launch = true
  count = length(data.aws_availability_zones.az.names)
  availability_zone = data.aws_availability_zones.az.names[count.index]
  tags = {
      Name = "Public"
  }
}

resource "aws_subnet" "private-subnets" {
  vpc_id = aws_vpc.vpc.id
  cidr_block = "10.0.${10+count.index}.0/24"
  map_public_ip_on_launch = false
  count = length(data.aws_availability_zones.az.names)
  availability_zone= data.aws_availability_zones.az.names[count.index]

  tags = {
      Name = "Private"
  }
}
#----------------------------------------------------------------------------
# Network Access Control Lists
#----------------------------------------------------------------------------
resource "aws_default_network_acl" "default" {
  default_network_acl_id = aws_vpc.vpc.default_network_acl_id
  
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 101
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  egress {
    protocol   = "tcp"
    rule_no    = 101
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

      ingress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 32768
    to_port    = 61000
  }

    egress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

}
#----------------------------------------------------------------------------
# Security Groups
#----------------------------------------------------------------------------
resource "aws_security_group" "ec2-security-group" { 
  name        = "ec2-sg"
  description = "Allows HTTP and HTTPS inbound traffic"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "allow http access for everyone"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "allow https access for everyone"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "allow ssh access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "alb-sg" {
  name        = "alb-sg"
  description = "Application Load Balancer Security Group"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "Allow http access to the ALB"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow https access to the ALB"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks =  ["0.0.0.0/0"]
  }
}

#----------------------------------------------------------------------------
# Auto Scaling Group
#----------------------------------------------------------------------------
resource "aws_launch_template" "asg-launch-template" {
  name_prefix            = "launch-template"
  image_id               = "ami-0323c3dd2da7fb37d"
  instance_type          = "t2.micro"
  key_name               = var.key-pair
  user_data              = filebase64("${path.module}/bootstrap.sh")
  vpc_security_group_ids = [aws_security_group.ec2-security-group.id]
}

resource "aws_autoscaling_group" "autoscaling-group" {  
  desired_capacity          = 1
  max_size                  = 3
  min_size                  = 1
  health_check_grace_period = 180
  health_check_type         = "ELB" 
  vpc_zone_identifier       = aws_subnet.public-subnets.*.id
  depends_on                = [aws_subnet.public-subnets]

  launch_template {
    id      = aws_launch_template.asg-launch-template.id
    version = "$Latest"
  }
}

resource "aws_autoscaling_attachment" "asg-attach" {
  autoscaling_group_name = aws_autoscaling_group.autoscaling-group.id
  alb_target_group_arn   = aws_alb_target_group.alb-target.arn
}

resource "aws_autoscaling_policy" "scale-up" {
  name                   = "Scale Up Policy"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 240
  autoscaling_group_name = aws_autoscaling_group.autoscaling-group.name
}

resource "aws_autoscaling_policy" "scale-down" {
  name                   = "Scale Down Policy"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 240
  autoscaling_group_name = aws_autoscaling_group.autoscaling-group.name
}

#----------------------------------------------------------------------------
# Cloud Watch Alarms and Groups
#----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "cw-cpu-scale-up" {
  alarm_name                = "Instance Scale Up"
  alarm_description         = "Scale instances up when CPU load is greater than 80%"
  comparison_operator       = "GreaterThanOrEqualToThreshold"
  evaluation_periods        = "3"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "60"
  statistic                 = "Average"
  threshold                 = "80"
  insufficient_data_actions = []

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.autoscaling-group.name
  }

  alarm_actions     = [aws_autoscaling_policy.scale-up.arn]
}

resource "aws_cloudwatch_metric_alarm" "cw-cpu-scale-down" {
  alarm_name                = "Instance Scale Down"
  alarm_description         = "Scale instances down when CPU load is less than 15%"
  comparison_operator       = "LessThanOrEqualToThreshold"
  evaluation_periods        = "3"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "60"
  statistic                 = "Average"
  threshold                 = "15"
  insufficient_data_actions = []

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.autoscaling-group.name
  }

  alarm_actions     = [aws_autoscaling_policy.scale-down.arn]
}

resource "aws_cloudwatch_log_group" "vpc-cwl-group" {
  name = "VPC-Flow-Logs"
}

#----------------------------------------------------------------------------
# Elastic Load Balancer
#----------------------------------------------------------------------------
resource "aws_alb" "alb" {
  name                       = "tf-web-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb-sg.id]
  subnets                    = aws_subnet.public-subnets.*.id
  enable_deletion_protection = false

  tags = {
    Name = "ALB NAME"
  }
}

resource "aws_alb_target_group" "alb-target" {
  name     = "tf-alb-target"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id

  health_check {
    path                = "/healthy.html"
    port                = 80
    protocol            = "HTTP"
    healthy_threshold   = 5
    unhealthy_threshold = 2
    interval            = 5
    timeout             = 4
    matcher             = 200
  }
}

resource "aws_alb_listener" "alb-listener" {
  load_balancer_arn = aws_alb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_alb_target_group.alb-target.arn
  }
}