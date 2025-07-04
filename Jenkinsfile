pipeline{

one of the CLI outputs:
terraform output alb_dns_name

# Authenticate Docker with ECR:
aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin <your-account-id>.dkr.ecr.ap-south-1.amazonaws.com

# Build Docker image:
docker build -t django-service .

# Tag it with ECR Repo
docker tag django-service:latest <your-account-id>.dkr.ecr.ap-south-1.amazonaws.com/django-service:latest

# Push to ECR:
docker push <your-account-id>.dkr.ecr.ap-south-1.amazonaws.com/django-service:latest

##############

# after running the ECR creation Step push the image to the ecr:
export ECR_URL=$(terraform output -raw django_ecr_repo_url)
docker tag django-service:latest $ECR_URL:latest
docker push $ECR_URL:latest

}


stage('Terraform Infra') {
    dir('infrastructure') {
        sh 'terraform init && terraform apply -auto-approve'
    }
}

stage('Terraform ECS + Django') {
    dir('ecs-django-service') {
        sh 'terraform init && terraform apply -auto-approve'
    }
}
