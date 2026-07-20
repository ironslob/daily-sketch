variable "name_prefix" {
  description = "Resource name prefix."
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix for metric dimensions."
  type        = string
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix for metric dimensions."
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS cluster name."
  type        = string
}

variable "ecs_service_name" {
  description = "ECS service name."
  type        = string
}

variable "rds_instance_id" {
  description = "RDS instance identifier."
  type        = string
}

variable "alarm_sns_topic_arn" {
  description = "Optional SNS topic for alarm actions."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
