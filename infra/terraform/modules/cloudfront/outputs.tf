output "distribution_id" {
  description = "CloudFront distribution ID."
  value       = aws_cloudfront_distribution.media.id
}

output "distribution_arn" {
  description = "CloudFront distribution ARN."
  value       = aws_cloudfront_distribution.media.arn
}

output "distribution_domain_name" {
  description = "CloudFront domain name (set STORAGE_PUBLIC_ENDPOINT to https://this when serving derivatives via CDN)."
  value       = aws_cloudfront_distribution.media.domain_name
}

output "distribution_hosted_zone_id" {
  description = "Route53 hosted zone ID for alias records."
  value       = aws_cloudfront_distribution.media.hosted_zone_id
}
