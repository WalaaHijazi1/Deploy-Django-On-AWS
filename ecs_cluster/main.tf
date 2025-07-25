terraform {
  backend "s3" {}
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# reading outputs from the infra's state file in S3.
data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = "django-terraform-state-files"
    key    = "infra/terraform.tfstate"
    region = "ap-south-1"
  }
}


provider "aws" {
  region = "ap-south-1"
}

data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

# IAM Roles ===========================================================
resource "aws_iam_role" "ecs_instance_role" {
  name = "ecsInstanceRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
  
  lifecycle {
    ignore_changes = [name]
  }
}

resource "aws_iam_role_policy_attachment" "ecs_instance_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ecs_ecr_access" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
  
  lifecycle {
    ignore_changes = [name]
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_exec_attach" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ecr_access" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "ecsInstanceProfile-${md5(timestamp())}"
  role = aws_iam_role.ecs_instance_role.name
  
  lifecycle {
    ignore_changes = [name]
  }
}

# VPC Endpoints for ECR ================================================
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = data.terraform_remote_state.infra.outputs.vpc_id
  service_name        = "com.amazonaws.ap-south-1.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.ecs_instance_sg.id]
  subnet_ids          = data.terraform_remote_state.infra.outputs.private_subnet_ids
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = data.terraform_remote_state.infra.outputs.vpc_id
  service_name        = "com.amazonaws.ap-south-1.ecr.api"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.ecs_instance_sg.id]
  subnet_ids          = data.terraform_remote_state.infra.outputs.private_subnet_ids
  private_dns_enabled = true
}

# Security Groups =====================================================
resource "aws_security_group" "ecs_instance_sg" {
  name   = "ecs-instance-sg-${md5(timestamp())}"
  vpc_id = data.terraform_remote_state.infra.outputs.vpc_id

   # Allow ECS tasks to talk to each other (optional)
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
  from_port       = 8000
  to_port         = 8000
  protocol        = "tcp"
  security_groups = [data.terraform_remote_state.infra.outputs.alb_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  lifecycle {
    ignore_changes = [name]
  }
}

resource "aws_security_group" "ecs_task_sg" {
  name        = "ecs-task-sg-${md5(timestamp())}"
  description = "Allow ALB access to tasks"
  vpc_id      = data.terraform_remote_state.infra.outputs.vpc_id

  ingress {
    description     = "Allow from ALB"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [data.terraform_remote_state.infra.outputs.alb_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  lifecycle {
    ignore_changes = [name]
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "rds-sg-${md5(timestamp())}"
  description = "Allow ECS tasks to access RDS"
  vpc_id      = data.terraform_remote_state.infra.outputs.vpc_id

  ingress {
    description     = "MySQL from ECS tasks"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_task_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  lifecycle {
    ignore_changes = [name]
  }
}


# RDS Database ========================================================
resource "aws_db_instance" "default" {
  allocated_storage      = 10
  db_name                = "djangodb"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  username               = "admin2511"
  password               = var.aws_db_password
  parameter_group_name   = "default.mysql8.0"
  db_subnet_group_name   = data.terraform_remote_state.infra.outputs.db_subnet_group_name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true
}

# ECS Resources =======================================================
resource "aws_ecs_cluster" "django_cluster" {
  name = "django-cluster-${md5(timestamp())}"
  
  lifecycle {
    ignore_changes = [name]
  }
}

# ECS Instances =======================================================
resource "aws_instance" "ecs_instance_a" {
  ami                         = data.aws_ssm_parameter.ecs_ami.value
  instance_type               = "t3.micro"
  subnet_id                   = data.terraform_remote_state.infra.outputs.private_subnet_ids[0]
  iam_instance_profile        = aws_iam_instance_profile.ecs_instance_profile.name
  vpc_security_group_ids      = [aws_security_group.ecs_instance_sg.id]
  associate_public_ip_address = false
  depends_on                  = [data.terraform_remote_state.infra]

  user_data = <<-EOF
              #!/bin/bash
              echo "ECS_CLUSTER=${aws_ecs_cluster.django_cluster.name}" >> /etc/ecs/ecs.config
              EOF

  tags = {
    Name = "ecs-instance-a-${md5(timestamp())}"
  }
  
  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_instance" "ecs_instance_b" {
  ami                         = data.aws_ssm_parameter.ecs_ami.value
  instance_type               = "t3.micro"
  subnet_id                   = data.terraform_remote_state.infra.outputs.private_subnet_ids[1]
  iam_instance_profile        = aws_iam_instance_profile.ecs_instance_profile.name
  vpc_security_group_ids      = [aws_security_group.ecs_instance_sg.id]
  associate_public_ip_address = false
  depends_on                  = [data.terraform_remote_state.infra]

  user_data = <<-EOF
              #!/bin/bash
              echo "ECS_CLUSTER=${aws_ecs_cluster.django_cluster.name}" >> /etc/ecs/ecs.config
              EOF

  tags = {
    Name = "ecs-instance-b-${md5(timestamp())}"
  }
  
  lifecycle {
    ignore_changes = [tags]
  }
}


# ECS Task Definition =================================================
resource "aws_ecs_task_definition" "django_task" {
  family                   = "django-task-${md5(timestamp())}"
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

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/django-task"
        "awslogs-region"        = "ap-south-1"
        "awslogs-stream-prefix" = "ecs"
      }
    }

    environment = [
      { name = "DB_NAME",     value = aws_db_instance.default.db_name },
      { name = "DB_USER",     value = aws_db_instance.default.username },
      { name = "DB_PASSWORD", value = var.aws_db_password },
      { name = "DB_HOST",     value = aws_db_instance.default.address },
      { name = "DB_PORT",     value = "3306" },
      { name = "DJANGO_DEBUG", value = "False" },
      { name = "ALLOWED_HOSTS", value = data.terraform_remote_state.infra.outputs.alb_dns }
    ]

    essential = true

    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:8000/ || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])
  
  lifecycle {
    ignore_changes = [family]
  }
}

# ECS Service =========================================================
resource "aws_ecs_service" "django_service" {
  name            = "django-service-${md5(timestamp())}"
  cluster         = aws_ecs_cluster.django_cluster.id
  task_definition = aws_ecs_task_definition.django_task.arn
  desired_count   = 2
  launch_type     = "EC2"


  load_balancer {
    target_group_arn = data.terraform_remote_state.infra.outputs.target_group_arn
    container_name   = "django-container"
    container_port   = 8000
  }

  depends_on = [
    aws_iam_role_policy_attachment.ecr_access,
    aws_db_instance.default,
    aws_vpc_endpoint.ecr_dkr,
    aws_vpc_endpoint.ecr_api
  ]
  
  lifecycle {
    ignore_changes = [name]
  }
}