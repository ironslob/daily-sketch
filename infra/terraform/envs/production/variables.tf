variable "aws_region" {
  description = "Primary AWS region for compute, RDS, and S3."
  type        = string
  default     = "eu-west-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR."
  type        = string
  default     = "10.30.0.0/16"
}

variable "media_bucket_name" {
  description = "Globally unique private media bucket name."
  type        = string
}

variable "api_domain_name" {
  description = "Public API hostname (ACM certificate must cover this)."
  type        = string
}

variable "api_acm_certificate_arn" {
  description = "ACM certificate ARN in the same region as the ALB."
  type        = string
}

variable "cdn_domain_name" {
  description = "Optional CloudFront custom domain for derivative media."
  type        = string
  default     = ""
}

variable "cdn_acm_certificate_arn" {
  description = "Optional ACM certificate ARN in us-east-1 for the CDN domain."
  type        = string
  default     = null
}

variable "backend_image" {
  description = "Container image URI for the backend."
  type        = string
}

variable "backend_desired_count" {
  description = "Desired ECS task count."
  type        = number
  default     = 2
}

variable "backend_cpu" {
  description = "Task CPU units."
  type        = number
  default     = 1024
}

variable "backend_memory" {
  description = "Task memory (MiB)."
  type        = number
  default     = 2048
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.small"
}

variable "db_allocated_storage_gb" {
  description = "RDS allocated storage (GB)."
  type        = number
  default     = 50
}

variable "db_max_allocated_storage_gb" {
  description = "RDS max autoscaling storage (GB)."
  type        = number
  default     = 200
}

variable "db_backup_retention_days" {
  description = "RDS backup retention days."
  type        = number
  default     = 14
}

variable "log_retention_days" {
  description = "CloudWatch log retention."
  type        = number
  default     = 90
}

variable "log_level" {
  description = "Backend LOG_LEVEL."
  type        = string
  default     = "INFO"
}

variable "release_version" {
  description = "RELEASE_VERSION."
  type        = string
}

variable "commit_sha" {
  description = "COMMIT_SHA for /health/version."
  type        = string
}

variable "build_timestamp" {
  description = "BUILD_TIMESTAMP for /health/version."
  type        = string
}

variable "descope_project_id" {
  description = "Descope project ID."
  type        = string
}

variable "descope_audience" {
  description = "Optional JWT audience. Only set when Descope JWT templates include a custom aud claim; leave empty otherwise."
  type        = string
  default     = ""
}

variable "prompt_date_timezone" {
  description = "PROMPT_DATE_TIMEZONE."
  type        = string
  default     = "UTC"
}

variable "creative_session_expiry_seconds" {
  description = "CREATIVE_SESSION_EXPIRY_SECONDS."
  type        = number
  default     = 86400
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarm actions (recommended in production)."
  type        = string
  default     = null
}

variable "moderation_operator_token" {
  description = "MODERATION_OPERATOR_TOKEN (sensitive — set in terraform.tfvars, never commit)."
  type        = string
  sensitive   = true
}

variable "sentry_dsn" {
  description = "Optional Sentry DSN."
  type        = string
  default     = null
  sensitive   = true
}

variable "alert_webhook_url" {
  description = "Optional alert webhook URL."
  type        = string
  default     = null
  sensitive   = true
}
