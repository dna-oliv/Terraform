provider "aws" {
  region = var.region
}

data "aws_availability_zones" "az" {}

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

resource "aws_launch_template" "asg-launch-template" {
  name_prefix            = "launch-template"
  image_id               = "ami-0323c3dd2da7fb37d"
  instance_type          = "t2.micro"
  key_name               = var.key-pair
  user_data              = filebase64("${path.module}/bootstrap.sh")
  vpc_security_group_ids = [aws_security_group.ec2-security-group.id]
}

resource "aws_autoscaling_group" "autoscaling-group" {  
  desired_capacity    = 1
  max_size            = 3
  min_size            = 1
  vpc_zone_identifier = aws_subnet.public-subnets.*.id
  depends_on          = [aws_subnet.public-subnets]

  launch_template {
    id      = aws_launch_template.asg-launch-template.id
    version = "$Latest"
  }
}