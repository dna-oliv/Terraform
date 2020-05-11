provider "aws" {
  region = var.region
}

data "aws_availability_zones" "az" {}

resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
}
resource "aws_subnet" "public-subnets" {
  vpc_id = aws_vpc.VPC.id
  cidr_block = "10.0.${0+count.index}.0/24"
  map_public_ip_on_launch = true
  count = length(data.aws_availability_zones.az.names)
  availability_zone = data.aws_availability_zones.az.names[count.index]
  tags = {
      Name = "Public"
  }
}
resource "aws_subnet" "private-subnets" {
  vpc_id = aws_vpc.VPC.id
  cidr_block = "10.0.${10+count.index}.0/24"
  map_public_ip_on_launch = false
  count = length(data.aws_availability_zones.az.names)
  availability_zone= data.aws_availability_zones.az.names[count.index]

  tags = {
      Name = "Private"
  }
}