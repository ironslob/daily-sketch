locals {
  common_tags = merge(var.tags, {
    Module = "secrets"
  })
}

resource "aws_secretsmanager_secret" "database_url" {
  name                    = "${var.name_prefix}/database-url"
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-database-url"
  })
}

resource "aws_secretsmanager_secret" "moderation_operator_token" {
  name                    = "${var.name_prefix}/moderation-operator-token"
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-moderation-operator-token"
  })
}

resource "aws_secretsmanager_secret" "sentry_dsn" {
  name                    = "${var.name_prefix}/sentry-dsn"
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-sentry-dsn"
  })
}

resource "aws_secretsmanager_secret" "alert_webhook_url" {
  name                    = "${var.name_prefix}/alert-webhook-url"
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-alert-webhook-url"
  })
}

resource "aws_secretsmanager_secret_version" "database_url" {
  count = var.database_url == null ? 0 : 1

  secret_id     = aws_secretsmanager_secret.database_url.id
  secret_string = var.database_url
}

resource "aws_secretsmanager_secret_version" "moderation_operator_token" {
  count = var.moderation_operator_token == null ? 0 : 1

  secret_id     = aws_secretsmanager_secret.moderation_operator_token.id
  secret_string = var.moderation_operator_token
}

resource "aws_secretsmanager_secret_version" "sentry_dsn" {
  count = var.sentry_dsn == null ? 0 : 1

  secret_id     = aws_secretsmanager_secret.sentry_dsn.id
  secret_string = var.sentry_dsn
}

resource "aws_secretsmanager_secret_version" "alert_webhook_url" {
  count = var.alert_webhook_url == null ? 0 : 1

  secret_id     = aws_secretsmanager_secret.alert_webhook_url.id
  secret_string = var.alert_webhook_url
}
