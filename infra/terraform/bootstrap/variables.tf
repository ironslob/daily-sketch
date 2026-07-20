variable "aws_region" {
  description = "AWS region for the remote state bucket and lock table."
  type        = string
  default     = "eu-west-1"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state objects."
  type        = string
}

variable "lock_table_name" {
  description = "DynamoDB table name for Terraform state locking."
  type        = string
  default     = "dailysketch-terraform-locks"
}

variable "enable_bucket_replication" {
  description = "Optional cross-region replication (disabled by default for cost)."
  type        = bool
  default     = false
}
