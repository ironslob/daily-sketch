resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${var.name_prefix}/backend"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-backend-logs"
  })
}

resource "aws_cloudwatch_log_group" "jobs" {
  name              = "/ecs/${var.name_prefix}/jobs"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-jobs-logs"
  })
}
