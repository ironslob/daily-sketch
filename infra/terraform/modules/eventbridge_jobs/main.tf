locals {
  common_tags = merge(var.tags, {
    Module = "eventbridge_jobs"
  })
}

data "aws_iam_policy_document" "events_assume" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "events_run_task" {
  statement {
    sid    = "RunEcsTasks"
    effect = "Allow"

    actions = [
      "ecs:RunTask",
    ]

    resources = [
      replace(var.task_definition_arn, "/:\\d+$/", ":*"),
    ]

    condition {
      test     = "ArnLike"
      variable = "ecs:cluster"
      values   = [var.cluster_arn]
    }
  }

  statement {
    sid    = "PassRoles"
    effect = "Allow"

    actions = [
      "iam:PassRole",
    ]

    resources = [
      var.execution_role_arn,
      var.task_role_arn,
    ]
  }
}

resource "aws_iam_role" "events" {
  name               = "${var.name_prefix}-events-ecs"
  assume_role_policy = data.aws_iam_policy_document.events_assume.json

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-events-ecs"
  })
}

resource "aws_iam_role_policy" "events" {
  name   = "${var.name_prefix}-events-ecs"
  role   = aws_iam_role.events.id
  policy = data.aws_iam_policy_document.events_run_task.json
}

resource "aws_cloudwatch_event_rule" "job" {
  for_each = var.jobs

  name                = "${var.name_prefix}-${each.key}"
  description         = "Run Daily Sketch job ${each.key}"
  schedule_expression = each.value.schedule_expression

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-${each.key}"
    Job  = each.key
  })
}

resource "aws_cloudwatch_event_target" "job" {
  for_each = var.jobs

  rule      = aws_cloudwatch_event_rule.job[each.key].name
  target_id = "${each.key}-ecs"
  arn       = var.cluster_arn
  role_arn  = aws_iam_role.events.arn

  ecs_target {
    task_count          = 1
    task_definition_arn = var.task_definition_arn
    launch_type         = "FARGATE"
    platform_version    = "LATEST"

    network_configuration {
      subnets          = var.private_subnet_ids
      security_groups  = [var.ecs_security_group_id]
      assign_public_ip = false
    }
  }

  input = jsonencode({
    containerOverrides = [
      {
        name        = var.container_name
        command     = ["python", "-m", each.value.module_path]
        environment = []
      }
    ]
  })
}
