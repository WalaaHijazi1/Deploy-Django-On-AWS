terraform {
    backend "s3" {
        
    }
    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = "~> 5.0"
        }
    }
}

resource "aws_ecr_repository" "django_repo" {
    name = "django_service"
}