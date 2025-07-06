variable "db_password" {
	description = "A password for the data base"
	type        = string
	default     = "walaa2511"
}

variable "aws_db_password" {
	description = "an SQL database password"
	type        = string
	default     = "walaa2511"
}

variable "ecr_repo_url" {
  description = "ECR Repository URL for ECS container image"
  type        = string
}

