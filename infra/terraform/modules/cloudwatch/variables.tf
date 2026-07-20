variable "name_prefix" {
  description = "Resource name prefix."
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log retention."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}

locals {
  common_tags = merge(var.tags, {
    Module = "cloudwatch"
  })
}
