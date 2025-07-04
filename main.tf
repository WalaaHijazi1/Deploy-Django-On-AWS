terraform {
   required_providers {
	aws = {
	   source = "hashicorp/aws"
        version = "~> 5.0"
    }
  }
}


provider "aws" {
   region  = "ap-south-1"
}


data "aws_ami" "ubuntu" {
    most_recent  = true

    filter {
      name   = "name" 
      values = ["ubuntu/images/hvm-ssd/ubuntu-noble-24.04-amd64-server-*"]
   }

    filter {
      name    = "virtualization-type"
      values  = ["hvm"]
   }

    owners = ["099720109477"]
}


resource "aws_vpc" "main" {
   cidr_block          = "10.0.0.0/16"
   instance_tenancy    = "default"

    tags = {
	Name = "main_cicd_vpc"
   }
}

resource "aws_internet_gateway" "main_gw" {
    vpc_id = aws_vpc.main.id

    tags = {
        Name = "main_internet_gw"
    }
}

resource "aws_subnet" "subnet_a" {
   vpc_id              = aws_vpc.main.id
   cidr_block          = "10.0.1.0/24"
   availability_zone   = "ap-south-1a"

   tags = {
      Name = "subnet_cicd_a"
  }
}

resource "aws_subnet" "subnet_b" {
   vpc_id              = aws_vpc.main.id
   cidr_block          = "10.0.2.0/24"
   availability_zone   = "ap-south-1b"

   tags = {
       Name   = "subnet_cicd_b"
   }
}

resource "aws_subnet" "private_subnet_a" {
    vpc_id              = aws_vpc.main.id
    cidr_block          = "10.0.3.0/24"
    availability_zone   = "ap-south-1a"


    tags = {
        Name = "private_subnet_cicd_a"
  }
}


resource "aws_subnet" "private_subnet_b" {
    vpc_id              = aws_vpc.main.id
    cidr_block          = "10.0.4.0/24"
    availability_zone   = "ap-south-1b"

    tags = {
       Name = "private_subnet_cicd_b"
  }
}


resource "aws_eip" "nat" {
    vpc  = true
}


resource "aws_route_table_association" "a_public" {
  subnet_id      = aws_subnet.subnet_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "b_public" {
  subnet_id      = aws_subnet.subnet_b.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "a_private" {
  subnet_id      = aws_subnet.private_subnet_a.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "b_private" {
  subnet_id      = aws_subnet.private_subnet_b.id
  route_table_id = aws_route_table.private_rt_b.id
}


resource "aws_alb_target_group" "app_tg" {
    name         = "django-target-group"
    port         = 80
    protocol     = "HTTP"
    vpc_id       = aws_vpc.main.id
    target_type  = "instance"

    health_check {
	path                 = "/"
	interval             = 30
	timeout              = 5
	healthy_threshold    = 2
	unhealthy_threshold  = 2
	matcher              = "200"
    }

    tags = {
	Name = "Django-tg"
    }
}


resource "aws_alb_target_group_attachment" "web_a" {
	target_group_arn  = aws_alb_target_group.app_tg.arn
	target_id         = aws_instance.public_instance_a.id
	port              = 80
}


resource "aws_alb_target_group_attachment" "web_b" {
	target_group_arn  = aws_alb_target_group.app_tg.arn
	target_id         = aws_instance.public_instance_b.id
	port              = 80
}


resource "aws_alb" "app_LoadBalancer" {
    name                 = "django-LoadBalancer"
    internal             = false
    load_balancer_type   = "application"
    security_groups      = [var.alb_security_group.id]
    subnets              = [aws_subnet.subnet_a.id,aws_subnet.subnet_b.id]

    enable_deletion_protection  = true

    tags = {
	Environment = "production"
    }
}


resource "aws_alb_listener" "http" {
    load_balance_arn   = aws_alb.app_LoadBalancer.arn
    port               = 80
    protocol           = "HTTP"

    default_action{
        type             = "forward"
	    target_group_arn = aws_alb_target_group.app_tg.arn
    }
}

resource "aws_nat_gateway" "nat_gw_a" {
    allocation_id = aws_eip.nat_gw_a.id
    subnet_id     = aws_subnet.subnet_a.id

    tags = {
        Name = "gw NT A"
    }
}

resource "aws_nat_gateway" "nat_gw_b" {
    allocation_id  = aws_eip.nat_gw_b.id
    subnet_id      = aws_subnet.subnet_b.id

    tags = {
        Name = "gw NAT B"
    }
}

resource "aws_security_group"  "public_rt" {
    vpc_id = aws_vpc.main.id

    route {
        cidr_block    = "0.0.0.0/0"
        gateaway_id   = aws_internet_gateway.main_gw.id
    }
}

resource "aws_route_table" "private_rt" {
    vpc_id  = aws_vpc.main.id

    route {
        cidr_block   = "0.0.0.0/0"
        gateaway_id  = aws_nat_gateway.nat_gw_a.id 
    }
}

resource "aws_route_table" "private_rt" {
    vpc_id  = aws_vpc.main.id

    route {
        # Any outbound traffic from EC2 instances in this subnet going to the internet will go through the NAT Gateway.
        cidr_block   = "0.0.0.0/0"
        gateaway_id  = aws_nat_gateway.nat_gw_b.id 
    }
}

