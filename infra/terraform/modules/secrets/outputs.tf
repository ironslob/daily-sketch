output "database_url_secret_arn" {
  description = "Secrets Manager ARN for DATABASE_URL."
  value       = aws_secretsmanager_secret.database_url.arn
}

output "moderation_operator_token_secret_arn" {
  description = "Secrets Manager ARN for MODERATION_OPERATOR_TOKEN."
  value       = aws_secretsmanager_secret.moderation_operator_token.arn
}

output "sentry_dsn_secret_arn" {
  description = "Secrets Manager ARN for SENTRY_DSN."
  value       = aws_secretsmanager_secret.sentry_dsn.arn
}

output "alert_webhook_url_secret_arn" {
  description = "Secrets Manager ARN for ALERT_WEBHOOK_URL."
  value       = aws_secretsmanager_secret.alert_webhook_url.arn
}

output "all_secret_arns" {
  description = "All secret ARNs referenced by ECS task roles."
  value = [
    aws_secretsmanager_secret.database_url.arn,
    aws_secretsmanager_secret.moderation_operator_token.arn,
    aws_secretsmanager_secret.sentry_dsn.arn,
    aws_secretsmanager_secret.alert_webhook_url.arn,
  ]
}
