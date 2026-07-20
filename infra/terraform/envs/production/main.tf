terraform {
  backend "s3" {
    bucket         = "REPLACE_AFTER_BOOTSTRAP"
    key            = "production/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "dailysketch-terraform-locks"
    encrypt        = true
  }

  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "dailysketch"
      Environment = "production"
      ManagedBy   = "terraform"
    }
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "dailysketch"
      Environment = "production"
      ManagedBy   = "terraform"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  name_prefix = "dailysketch-production"

  common_tags = {
    Environment = "production"
  }

  jobs = {
    upload_cleanup = {
      schedule_expression = "rate(1 hour)"
      module_path         = "app.jobs.upload_cleanup"
    }
    sketch_session_cleanup = {
      schedule_expression = "rate(1 hour)"
      module_path         = "app.jobs.sketch_session_cleanup"
    }
    idempotency_cleanup = {
      schedule_expression = "rate(6 hours)"
      module_path         = "app.jobs.idempotency_cleanup"
    }
    deleted_media_cleanup = {
      schedule_expression = "rate(24 hours)"
      module_path         = "app.jobs.deleted_media_cleanup"
    }
    missing_prompt_check = {
      schedule_expression = "cron(0 8 * * ? *)"
      module_path         = "app.jobs.missing_prompt_check"
    }
    account_deletion_finalize = {
      schedule_expression = "rate(1 hour)"
      module_path         = "app.jobs.account_deletion"
    }
  }

  storage_endpoint = "https://s3.${var.aws_region}.amazonaws.com"

  container_secret_arns = merge(
    {
      DATABASE_URL = module.secrets.database_url_secret_arn
    },
    var.moderation_operator_token != null ? {
      MODERATION_OPERATOR_TOKEN = module.secrets.moderation_operator_token_secret_arn
    } : {},
    var.sentry_dsn != null ? {
      SENTRY_DSN = module.secrets.sentry_dsn_secret_arn
    } : {},
    var.alert_webhook_url != null ? {
      ALERT_WEBHOOK_URL = module.secrets.alert_webhook_url_secret_arn
    } : {},
  )
}

module "networking" {
  source = "../../modules/networking"

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)
  tags               = local.common_tags
}

module "s3_media" {
  source = "../../modules/s3_media"

  bucket_name = var.media_bucket_name
  tags        = local.common_tags
}

module "cloudfront" {
  source = "../../modules/cloudfront"

  name_prefix                       = local.name_prefix
  media_bucket_id                   = module.s3_media.bucket_id
  media_bucket_arn                  = module.s3_media.bucket_arn
  media_bucket_regional_domain_name = module.s3_media.bucket_regional_domain_name
  aliases                           = var.cdn_domain_name == "" ? [] : [var.cdn_domain_name]
  acm_certificate_arn               = var.cdn_acm_certificate_arn
  tags                              = local.common_tags

  providers = {
    aws = aws.us_east_1
  }
}

data "aws_iam_policy_document" "media_bucket_cloudfront" {
  statement {
    sid    = "AllowCloudFrontServiceRead"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${module.s3_media.bucket_arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [module.cloudfront.distribution_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "media_cloudfront_read" {
  bucket = module.s3_media.bucket_id
  policy = data.aws_iam_policy_document.media_bucket_cloudfront.json
}

module "rds" {
  source = "../../modules/rds"

  name_prefix              = local.name_prefix
  subnet_ids               = module.networking.private_subnet_ids
  security_group_ids       = [module.networking.rds_security_group_id]
  instance_class           = var.db_instance_class
  allocated_storage_gb     = var.db_allocated_storage_gb
  max_allocated_storage_gb = var.db_max_allocated_storage_gb
  backup_retention_days    = var.db_backup_retention_days
  deletion_protection      = true
  skip_final_snapshot      = false
  tags                     = local.common_tags
}

module "secrets" {
  source = "../../modules/secrets"

  name_prefix               = local.name_prefix
  database_url              = module.rds.database_url_asyncpg
  moderation_operator_token = var.moderation_operator_token
  sentry_dsn                = var.sentry_dsn
  alert_webhook_url         = var.alert_webhook_url
  tags                      = local.common_tags
}

module "iam_backend" {
  source = "../../modules/iam_backend"

  name_prefix      = local.name_prefix
  media_bucket_arn = module.s3_media.bucket_arn
  secret_arns      = module.secrets.all_secret_arns
  tags             = local.common_tags
}

module "cloudwatch" {
  source = "../../modules/cloudwatch"

  name_prefix        = local.name_prefix
  log_retention_days = var.log_retention_days
  tags               = local.common_tags
}

module "ecs" {
  source = "../../modules/ecs"

  name_prefix           = local.name_prefix
  vpc_id                = module.networking.vpc_id
  public_subnet_ids     = module.networking.public_subnet_ids
  private_subnet_ids    = module.networking.private_subnet_ids
  alb_security_group_id = module.networking.alb_security_group_id
  ecs_security_group_id = module.networking.ecs_tasks_security_group_id
  execution_role_arn    = module.iam_backend.execution_role_arn
  task_role_arn         = module.iam_backend.task_role_arn
  container_image       = var.backend_image
  desired_count         = var.backend_desired_count
  cpu                   = var.backend_cpu
  memory                = var.backend_memory
  api_domain_name       = var.api_domain_name
  acm_certificate_arn   = var.api_acm_certificate_arn
  log_group_name        = module.cloudwatch.backend_log_group_name
  environment_variables = {
    APP_ENV                       = "production"
    LOG_LEVEL                     = var.log_level
    API_PUBLIC_URL                = "https://${var.api_domain_name}"
    RELEASE_VERSION               = var.release_version
    COMMIT_SHA                    = var.commit_sha
    BUILD_TIMESTAMP               = var.build_timestamp
    DB_SSL_REQUIRE                = "true"
    METRICS_ENABLED               = "true"
    DESCOPE_PROJECT_ID            = var.descope_project_id
    DESCOPE_ISSUER                = var.descope_issuer
    DESCOPE_AUDIENCE              = var.descope_audience
    STORAGE_ENDPOINT              = local.storage_endpoint
    STORAGE_PUBLIC_ENDPOINT       = var.cdn_domain_name != "" ? "https://${var.cdn_domain_name}" : local.storage_endpoint
    STORAGE_REGION                = var.aws_region
    STORAGE_BUCKET                = module.s3_media.bucket_id
    STORAGE_USE_SSL               = "true"
    PROMPT_DATE_TIMEZONE          = var.prompt_date_timezone
    SKETCH_SESSION_EXPIRY_SECONDS = tostring(var.sketch_session_expiry_seconds)
  }
  secret_arns = local.container_secret_arns
  tags        = local.common_tags

  depends_on = [module.cloudwatch]
}

module "monitoring_alarms" {
  source = "../../modules/monitoring_alarms"

  name_prefix             = local.name_prefix
  alb_arn_suffix          = module.ecs.alb_arn_suffix
  target_group_arn_suffix = module.ecs.target_group_arn_suffix
  ecs_cluster_name        = module.ecs.cluster_name
  ecs_service_name        = module.ecs.service_name
  rds_instance_id         = "${local.name_prefix}-postgres"
  alarm_sns_topic_arn     = var.alarm_sns_topic_arn
  tags                    = local.common_tags
}

module "eventbridge_jobs" {
  source = "../../modules/eventbridge_jobs"

  name_prefix           = local.name_prefix
  cluster_arn           = module.ecs.cluster_arn
  task_definition_arn   = module.ecs.task_definition_arn
  container_name        = module.ecs.container_name
  private_subnet_ids    = module.networking.private_subnet_ids
  ecs_security_group_id = module.networking.ecs_tasks_security_group_id
  execution_role_arn    = module.iam_backend.execution_role_arn
  task_role_arn         = module.iam_backend.task_role_arn
  log_group_name        = module.cloudwatch.jobs_log_group_name
  jobs                  = local.jobs
  tags                  = local.common_tags
}
