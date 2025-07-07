# Same terraform & provider block
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

module "infra" {
  source = "../infrastructure"
}

data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}


# ECS EC2 IAM Role
# Create ECS instance role
resource "aws_iam_role" "ecs_instance_role" {
  name = "ecsInstanceRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_instance_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "ecsInstanceProfile-1"
  role = aws_iam_role.ecs_instance_role.name
}

# ECS task execution role
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_exec_attach" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

#  This is all you need. DELETE the following blocks completely:
# - data "aws_iam_role" "ecs_task_execution_role"
# - resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy"


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

resource "aws_security_group" "db_sg" {
  name   = "db-sg"
  vpc_id = module.infra.vpc_id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_instance_sg.id] # Allow ECS instances to connect
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "default" {
  allocated_storage      = 10
  db_name                = "djangodb"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  username               = "admin2511"
  password               = var.aws_db_password
  parameter_group_name   = "default.mysql8.0"
  db_subnet_group_name   = module.infra.db_subnet_group_name
  vpc_security_group_ids = [aws_security_group.db_sg.id]  # or use rds_sg if that's what you created
  skip_final_snapshot    = true

  tags = {
    Name = "django-rds-mysql"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  description = "Allow ECS instances to access RDS on port 3306"
  vpc_id      = module.infra.vpc_id

  ingress {
    description     = "Allow MySQL access from ECS instances"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_instance_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds-sg"
  }
}


# ECS Instance A
resource "aws_instance" "ecs_instance_a" {
  ami                         = data.aws_ssm_parameter.ecs_ami.value
  instance_type               = "t3.micro"
  subnet_id                   = module.infra.private_subnet_id_a
  iam_instance_profile        = aws_iam_instance_profile.ecs_instance_profile.name
  associate_public_ip_address = false
  security_groups             = [aws_security_group.ecs_instance_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              echo "ECS_CLUSTER=${aws_ecs_cluster.django_cluster.name}" >> /etc/ecs/ecs.config
              yum install -y ecs-init
              systemctl enable --now ecs
              EOF

  tags = {
    Name = "ecs-instance-a"
  }
}

# ECS Instance B
resource "aws_instance" "ecs_instance_b" {
  ami                         = data.aws_ssm_parameter.ecs_ami.value
  instance_type               = "t3.micro"
  subnet_id                   = module.infra.private_subnet_id_b
  iam_instance_profile        = aws_iam_instance_profile.ecs_instance_profile.name
  associate_public_ip_address = false
  security_groups             = [aws_security_group.ecs_instance_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              echo "ECS_CLUSTER=${aws_ecs_cluster.django_cluster.name}" >> /etc/ecs/ecs.config
              yum install -y ecs-init
              systemctl enable --now ecs
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
    }],
    environment = [{
      name  = "DATABASE_URL"
      value = "mysql://admin2511:${var.aws_db_password}@rds-endpoint:3306/djangodb"
    }],
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