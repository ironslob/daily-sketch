variable "aws_region" {
  description = "Primary AWS region for compute, RDS, and S3."
  type        = string
  default     = "eu-west-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR."
  type        = string
  default     = "10.20.0.0/16"
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
  description = "Optional CloudFront custom domain for derivative media. Leave empty to use the default cloudfront.net domain."
  type        = string
  default     = ""
}

variable "cdn_acm_certificate_arn" {
  description = "Optional ACM certificate ARN in us-east-1 for the CDN domain."
  type        = string
  default     = null
}

variable "backend_image" {
  description = "Container image URI for the backend (ECR tag or digest)."
  type        = string
}

variable "backend_desired_count" {
  description = "Desired ECS task count."
  type        = number
  default     = 1
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage_gb" {
  description = "RDS allocated storage (GB)."
  type        = number
  default     = 20
}

variable "log_retention_days" {
  description = "CloudWatch log retention."
  type        = number
  default     = 14
}

variable "log_level" {
  description = "Backend LOG_LEVEL."
  type        = string
  default     = "INFO"
}

variable "release_version" {
  description = "RELEASE_VERSION baked into the running image metadata."
  type        = string
  default     = "0.1.0-staging"
}

variable "commit_sha" {
  description = "COMMIT_SHA for /health/version."
  type        = string
  default     = "unknown"
}

variable "build_timestamp" {
  description = "BUILD_TIMESTAMP for /health/version."
  type        = string
  default     = "unknown"
}

variable "descope_project_id" {
  description = "Descope project ID (non-secret identifier)."
  type        = string
}

variable "descope_issuer" {
  description = "Descope JWT issuer URL."
  type        = string
}

variable "descope_audience" {
  description = "Descope JWT audience."
  type        = string
}

variable "prompt_date_timezone" {
  description = "PROMPT_DATE_TIMEZONE."
  type        = string
  default     = "UTC"
}

variable "sketch_session_expiry_seconds" {
  description = "SKETCH_SESSION_EXPIRY_SECONDS."
  type        = number
  default     = 86400
}

variable "alarm_sns_topic_arn" {
  description = "Optional SNS topic ARN for CloudWatch alarm actions."
  type        = string
  default     = null
}

variable "moderation_operator_token" {
  description = "Optional MODERATION_OPERATOR_TOKEN (sensitive — set in terraform.tfvars, never commit)."
  type        = string
  default     = null
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
