variable "name_prefix" {
  description = "Resource name prefix, e.g. dailysketch-staging."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZ names to spread subnets across (minimum two)."
  type        = list(string)
}

variable "tags" {
  description = "Additional tags applied to networking resources."
  type        = map(string)
  default     = {}
}
