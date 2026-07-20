variable "name_prefix" {
  description = "Resource name prefix."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets for the ALB."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnets for ECS tasks."
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group for the ALB."
  type        = string
}

variable "ecs_security_group_id" {
  description = "Security group for ECS tasks."
  type        = string
}

variable "execution_role_arn" {
  description = "ECS task execution role ARN."
  type        = string
}

variable "task_role_arn" {
  description = "ECS task role ARN."
  type        = string
}

variable "container_image" {
  description = "Full container image URI (ECR or registry)."
  type        = string
}

variable "container_port" {
  description = "Container listen port."
  type        = number
  default     = 8000
}

variable "desired_count" {
  description = "Desired ECS service task count."
  type        = number
  default     = 1
}

variable "cpu" {
  description = "Task CPU units."
  type        = number
  default     = 512
}

variable "memory" {
  description = "Task memory (MiB)."
  type        = number
  default     = 1024
}

variable "api_domain_name" {
  description = "Public API hostname for the ALB listener."
  type        = string
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for the API domain (same region as ALB)."
  type        = string
}

variable "environment_variables" {
  description = "Plain environment variables for the backend container."
  type        = map(string)
  default     = {}
}

variable "secret_arns" {
  description = "Map of ENV_NAME => Secrets Manager ARN for container secrets."
  type        = map(string)
  default     = {}
}

variable "log_group_name" {
  description = "CloudWatch log group for container logs."
  type        = string
}

variable "health_check_path" {
  description = "ALB health check path."
  type        = string
  default     = "/health/live"
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
