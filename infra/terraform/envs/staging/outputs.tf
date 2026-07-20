output "api_url" {
  description = "Public API base URL."
  value       = "https://${var.api_domain_name}"
}

output "alb_dns_name" {
  description = "ALB DNS name — create a CNAME/alias from api_domain_name."
  value       = module.ecs.alb_dns_name
}

output "media_bucket_name" {
  description = "Private S3 media bucket."
  value       = module.s3_media.bucket_id
}

output "cloudfront_domain_name" {
  description = "CloudFront domain for derivative media (display/thumbnail only)."
  value       = module.cloudfront.distribution_domain_name
}

output "rds_endpoint" {
  description = "RDS hostname (credentials in Secrets Manager)."
  value       = module.rds.endpoint
}

output "database_url_secret_arn" {
  description = "Secrets Manager ARN containing DATABASE_URL."
  value       = module.secrets.database_url_secret_arn
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "ECS service name."
  value       = module.ecs.service_name
}

output "eventbridge_job_rules" {
  description = "Scheduled cleanup job rule ARNs."
  value       = module.eventbridge_jobs.rule_arns
}
