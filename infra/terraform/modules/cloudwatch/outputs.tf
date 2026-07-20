output "backend_log_group_name" {
  description = "CloudWatch log group for the backend service."
  value       = aws_cloudwatch_log_group.backend.name
}

output "jobs_log_group_name" {
  description = "CloudWatch log group for scheduled jobs."
  value       = aws_cloudwatch_log_group.jobs.name
}
