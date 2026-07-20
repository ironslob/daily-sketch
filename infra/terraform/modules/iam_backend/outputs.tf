output "task_role_arn" {
  description = "IAM role ARN assumed by backend ECS tasks."
  value       = aws_iam_role.task.arn
}

output "task_role_name" {
  description = "IAM role name for backend ECS tasks."
  value       = aws_iam_role.task.name
}

output "execution_role_arn" {
  description = "IAM role ARN for ECS task execution (pull image, logs, secrets)."
  value       = aws_iam_role.execution.arn
}

output "execution_role_name" {
  description = "IAM role name for ECS execution."
  value       = aws_iam_role.execution.name
}
