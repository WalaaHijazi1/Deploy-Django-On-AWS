output "django_ecr_repo_url" {
  value = aws_ecr_repository.django_repo.repository_url
}
