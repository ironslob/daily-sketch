variable "name_prefix" {
  description = "Resource name prefix."
  type        = string
}

variable "media_bucket_arn" {
  description = "ARN of the private media bucket."
  type        = string
}

variable "secret_arns" {
  description = "Secrets Manager ARNs the task may read."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
