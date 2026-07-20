output "cluster_arn" {
  description = "ECS cluster ARN."
  value       = aws_ecs_cluster.this.arn
}

output "cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.backend.name
}

output "task_definition_arn" {
  description = "Backend task definition ARN (used by EventBridge RunTask)."
  value       = aws_ecs_task_definition.backend.arn
}

output "task_definition_family" {
  description = "Backend task definition family."
  value       = aws_ecs_task_definition.backend.family
}

output "container_name" {
  description = "Primary container name."
  value       = local.container_name
}

output "alb_dns_name" {
  description = "ALB DNS name — point api_domain_name CNAME/alias here."
  value       = aws_lb.api.dns_name
}

output "alb_arn" {
  description = "ALB ARN."
  value       = aws_lb.api.arn
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix for CloudWatch metrics."
  value       = regex("loadbalancer/(.*)$", aws_lb.api.arn)[0]
}

output "target_group_arn_suffix" {
  description = "Target group ARN suffix for CloudWatch metrics."
  value       = regex("targetgroup/(.*)$", aws_lb_target_group.api.arn)[0]
}
