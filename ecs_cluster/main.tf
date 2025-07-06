terraform{
    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = "~> 5.0"
        }
    }
}

module "infra" {
  source = "../infrastructure"
}

module "ecr_repo" {
    source =../ecr_repository"
}

#used to fetch a value from AWS Systems Manager Parameter Store (SSM)
data "aws_ssm_parameter" "ecs_ami_al2023" {
    name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

rwsource "aws_iam_role" "ecs_instance_role" {
    name = "ec2InstanceRole"

    assume_role_policy = jsoncode({
        Version = "2012-10-17",
        Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]  
    })
}


resource "aws_iam_instance_profile" "ecs_instance_profile1" {
  name = "ecsInstanceProfile"
  role = aws_iam_role.ecs_instance_role.name
}


resource "aws_db_subnet_group" "db_subnet" {
  name       = "django-db-subnet-group"
  subnet_ids = [module.infra.private_subnet_id_a, module.infra.private_subnet_id_b]

  tags = {
    Name = "DjangoDBSubnetGroup"
  }
}


resource "aws_security_group" "db_sg" {
  name        = "db-sg"
  description = "Allow MySQL access from ECS EC2 instances only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL access from ECS"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_instance_sg.id]  # ?? only allow ECS instances
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_db_instance" "default" {
  allocated_storage    = 10
  db_name              = "django-db"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  username             = "admin2511"
  password             = var.aws_db_password
  parameter_group_name = "default.mysql8.0"
  skip_final_snapshot  = true
  db_subnet_group_name = aws_db_subnet_group.db_subnet.name
  vpc_security_group_ids = [aws_security_group.db_sg.id] # You should define a SG that allows ECS access on port 3306

  resource "aws_ecs_cluster" "django_cluster" {
    name = "django-cluster"
  }
}


resource "aws_ecs_task_definition" "django_task" {
    family                       = "django-task"
    network_mode                 = "bridge"
    requiries_compatibilities    = ["EC2"]
    cpu                          = "256"
    memory                       = "512"

    container_definitions = jsonencode ([
        {
            name         = "django"
            image        = "${module.ecr_repo.django_ecr_repo_url}:latest"
            essential    = true
            portMappings = [
                {
                    containerport  = 8000
                    hostport       = 8000
                    protocol       = "tcp"
                }
            ]
            environment = [
                { name = "DB_HOST", value = aws_db_instance.default.endpoint },
                { name = "DB_NAME", value = aws_db_instance.default.db_name },
                { name = "DB_USER", value = aws_db_instance.default.username },
                { name = "DB_PASSWORD", value = var.aws_db_password}
            ]

            execution_role_arn   = aws_iam_role.ecs_task_execution_role.arn
            task_role            = aws_iam_role.ecs_task_role.arn
        }
    ])
}

resource "aws_security_group" "ecs_instance_sg" {
  name   = "ecs-instance-sg"
  vpc_id = module.infra.vpc_id

  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    security_groups = [module.infra.alb_sg_id] # ALB SG
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_instance" "ecs_instance_a" {
  ami                         = data.aws_ssm_parameter.ecs_ami_al2023.value
  instance_type               = "t3.micro"
  subnet_id                   = module.infra.private_subnet_id_a
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ecs_instance_profile.name
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
  ami                         = data.data.aws_ssm_parameter.ecs_ami_al2023.value
  instance_type               = "t3.micro"
  subnet_id                   = module.infra.private_subnet_id_b
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ecs_instance_profile.name
  security_groups             = [aws_security_group.ecs_instance_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              echo ECS_CLUSTER=${aws_ecs_cluster.django_cluster.name} >> /etc/ecs/ecs.config
              EOF

  tags = {
    Name = "ecs-instance-a"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_instance_attach" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ecr_readonly_attach" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}


resource "aws_alb_listener" "http" {
    load_balance_arn   = var.alb_arn
    port               = 80
    protocol           = "HTTP"

    default_action{
        type             = "forward"
	    target_group_arn = var.target_group_arn
    }
}


resource "aws_ecs_service" "django_service" {
    name              = "django_service"
    cluster           = aws_ecs_cluster.django_cluster.id
    task_definition   = aws_ecs_task_definition.django_task.arn
    desired_count     = 2
    launch_type       = "EC2"

    
    network_configuration {
        subnets         = module.infra.private_subnet_ids
        security_groups = [module.infra.security_group_id]
    }

    load_balancer {
        target_group    = aws_alb_target_group.django_tg.arn
        container_name  = "django"
        container_port  = 8000
    }

    deployment_minimum_healthy_percent = 50
    deployment_maximum_percent         = 200

    depends_on = [module.infra]
}
