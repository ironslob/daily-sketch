variable "name_prefix" {
  description = "Resource name prefix."
  type        = string
}

variable "cluster_arn" {
  description = "ECS cluster ARN."
  type        = string
}

variable "task_definition_arn" {
  description = "Backend task definition ARN (family:revision)."
  type        = string
}

variable "container_name" {
  description = "Container name to override command on."
  type        = string
  default     = "backend"
}

variable "private_subnet_ids" {
  description = "Private subnets for Fargate job tasks."
  type        = list(string)
}

variable "ecs_security_group_id" {
  description = "Security group for job tasks."
  type        = string
}

variable "execution_role_arn" {
  description = "ECS execution role to pass to RunTask."
  type        = string
}

variable "task_role_arn" {
  description = "ECS task role to pass to RunTask."
  type        = string
}

variable "log_group_name" {
  description = "CloudWatch log group for job output."
  type        = string
}

variable "jobs" {
  description = "Map of job name => { schedule_expression, module_path }."
  type = map(object({
    schedule_expression = string
    module_path         = string
  }))
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
