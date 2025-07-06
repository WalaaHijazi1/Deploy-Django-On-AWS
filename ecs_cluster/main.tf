terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}


module "infra" {
  source = "../infrastructure"
}

provider "aws" {
  region = "ap-south-1"
}

data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

resource "aws_ecs_cluster" "django_cluster" {
  name = "django-cluster"
}

resource "aws_security_group" "ecs_instance_sg" {
  name   = "ecs-instance-sg"
  vpc_id = module.infra.vpc_id

  ingress {
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [module.infra.alb_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "ecs_instance_a" {
  ami                         = data.aws_ssm_parameter.ecs_ami.value
  instance_type               = "t3.micro"
  subnet_id                   = module.infra.private_subnet_id_a
  iam_instance_profile        = aws_iam_instance_profile.ecs_instance_profile.name
  associate_public_ip_address = false
  security_groups             = [aws_security_group.ecs_instance_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              echo ECS_CLUSTER=${aws_ecs_cluster.django_cluster.name} >> /etc/ecs/ecs.config
              EOF

  tags = {
    Name = "ecs-instance-a"
  }
}

resource "aws_instance" "ecs_instance_b" {
  ami                         = data.aws_ssm_parameter.ecs_ami.value
  instance_type               = "t3.micro"
  subnet_id                   = module.infra.private_subnet_id_b
  iam_instance_profile        = aws_iam_instance_profile.ecs_instance_profile.name
  associate_public_ip_address = false
  security_groups             = [aws_security_group.ecs_instance_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              echo ECS_CLUSTER=${aws_ecs_cluster.django_cluster.name} >> /etc/ecs/ecs.config
              EOF

  tags = {
    Name = "ecs-instance-b"
  }
}

resource "aws_ecs_task_definition" "django_task" {
  family                   = "django-task"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name      = "django-container"
    image     = var.ecr_repo_url
    portMappings = [{
      containerPort = 8000
      hostPort      = 8000
      protocol      = "tcp"
    }]
    environment = [{
      name  = "DATABASE_URL"
      value = "djangodb"
    }]
    essential = true
  }])
}

resource "aws_ecs_service" "django_service" {
  name            = "django-service"
  cluster         = aws_ecs_cluster.django_cluster.id
  launch_type     = "EC2"
  desired_count   = 2
  task_definition = aws_ecs_task_definition.django_task.arn

  load_balancer {
    target_group_arn = module.infra.target_group_arn
    container_name   = "django-container"
    container_port   = 8000
  }

  depends_on = [module.infra]
}