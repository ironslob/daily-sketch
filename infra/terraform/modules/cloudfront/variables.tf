variable "name_prefix" {
  description = "Resource name prefix."
  type        = string
}

variable "media_bucket_id" {
  description = "S3 media bucket name."
  type        = string
}

variable "media_bucket_arn" {
  description = "S3 media bucket ARN."
  type        = string
}

variable "media_bucket_regional_domain_name" {
  description = "Regional domain name of the media bucket."
  type        = string
}

variable "aliases" {
  description = "Optional custom domain aliases (requires ACM cert in us-east-1)."
  type        = list(string)
  default     = []
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN in us-east-1 for custom aliases (optional)."
  type        = string
  default     = null
}

variable "price_class" {
  description = "CloudFront price class."
  type        = string
  default     = "PriceClass_100"
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
