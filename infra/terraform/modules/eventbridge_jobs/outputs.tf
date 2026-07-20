output "events_role_arn" {
  description = "IAM role used by EventBridge to invoke ECS RunTask."
  value       = aws_iam_role.events.arn
}

output "rule_arns" {
  description = "Map of job name to EventBridge rule ARN."
  value       = { for name, rule in aws_cloudwatch_event_rule.job : name => rule.arn }
}
