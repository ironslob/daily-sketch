# Daily Sketch — AWS Terraform

Production-grade AWS infrastructure for Daily Sketch: VPC, private media storage, CloudFront for derivatives only, ECS Fargate API, RDS PostgreSQL, Secrets Manager, CloudWatch, and EventBridge scheduled jobs.

## Layout

```
infra/terraform/
├── bootstrap/          # One-time S3 + DynamoDB remote state (local state)
├── modules/
│   ├── networking/     # VPC, subnets, NAT, security groups
│   ├── s3_media/       # Private media bucket + lifecycle
│   ├── cloudfront/     # OAC distribution (display/thumbnail only)
│   ├── iam_backend/    # ECS task + execution roles (S3 least privilege)
│   ├── rds/            # PostgreSQL 16
│   ├── secrets/        # Secrets Manager shells (no values in git)
│   ├── ecs/            # Fargate service + ALB + ACM listener
│   ├── cloudwatch/     # Log groups
│   ├── monitoring_alarms/  # Alarm stubs (wire SNS before paging)
│   └── eventbridge_jobs/   # ECS RunTask schedules for cleanup jobs
└── envs/
    ├── staging/
    └── production/
```

## Bootstrap order

1. **Remote state** — `bootstrap/` creates the state bucket and lock table. See [bootstrap/README.md](./bootstrap/README.md).
2. **ACM certificates** (manual, outside Terraform):
   - API cert in the **same region** as the ALB (e.g. `eu-west-1`).
   - CDN cert in **us-east-1** if using a custom CloudFront domain.
3. **Container registry** — push `backend/Dockerfile` image to ECR; set `backend_image` in tfvars.
4. **Environment apply** — pick `envs/staging` or `envs/production`.

```bash
# After bootstrap, configure backend.tf bucket name in the chosen env, then:
cd infra/terraform/envs/staging
cp terraform.tfvars.example terraform.tfvars
# Edit tfvars: domains, Descope IDs, image tag, bucket name, ACM ARNs.
# Add sensitive values (moderation token, etc.) to terraform.tfvars — never commit.

terraform init
terraform plan
terraform apply
```

## Apply notes

- **Secrets**: RDS `DATABASE_URL` is generated and stored in Secrets Manager on first apply. Set `moderation_operator_token` (required for production) via sensitive tfvars or `TF_VAR_moderation_operator_token`.
- **DNS**: Point `api_domain_name` to the `alb_dns_name` output (Route53 alias recommended). Point `cdn_domain_name` to the CloudFront distribution.
- **S3 credentials on ECS**: The backend adapter currently expects `STORAGE_ACCESS_KEY` / `STORAGE_SECRET_KEY`. The IAM task role grants S3 access for future use; until the app uses the default credential chain, create a scoped IAM user for presigned URLs or extend the adapter to prefer task-role credentials when keys are unset.
- **CloudFront originals**: A viewer-request function blocks any URI containing `/original`. Only paths ending in `/display` or `/thumbnail` are served. Originals remain private in S3 and are accessed via short-lived signed URLs from the API.
- **Jobs**: EventBridge invokes the same task definition as the API with `python -m app.jobs.*` overrides. Logs go to `/ecs/{prefix}/jobs`.

### Scheduled jobs

| Job | Module path | Default schedule |
|-----|-------------|------------------|
| upload_cleanup | `app.jobs.upload_cleanup` | hourly |
| sketch_session_cleanup | `app.jobs.sketch_session_cleanup` | hourly |
| idempotency_cleanup | `app.jobs.idempotency_cleanup` | every 6 hours |
| deleted_media_cleanup | `app.jobs.deleted_media_cleanup` | daily |
| missing_prompt_check | `app.jobs.missing_prompt_check` | 08:00 UTC daily |
| account_deletion_finalize | `app.jobs.account_deletion` | hourly |

Adjust schedules in `envs/*/main.tf` `local.jobs`.

## Destroy warnings

- **Production RDS** has `deletion_protection = true` and takes a final snapshot. Disable protection only for intentional teardown.
- **S3 media bucket** may retain objects; empty the bucket before destroy or use `force_destroy` (not enabled by default).
- **Secrets Manager** uses a recovery window — secrets are recoverable for 7 days after delete.
- **CloudFront** distributions take 15+ minutes to disable/delete.
- Destroying **staging** skips final RDS snapshot by design — data loss is immediate.

```bash
cd infra/terraform/envs/staging
terraform destroy   # review plan carefully
```

## Cost notes (rough, eu-west-1)

| Resource | Staging (default tfvars) | Production (default tfvars) |
|----------|--------------------------|-------------------------------|
| NAT Gateway | ~$32/mo + data | ~$32/mo + data |
| ECS Fargate | 1 × 0.5 vCPU / 1 GB | 2 × 1 vCPU / 2 GB |
| RDS | db.t4g.micro | db.t4g.small |
| ALB | ~$16/mo + LCU | ~$16/mo + LCU |
| CloudFront | usage-based | usage-based |
| S3 | storage + requests | storage + requests |

Staging defaults minimize cost; production enables deletion protection, longer log retention, and multi-task ECS.

## Formatting

```bash
terraform fmt -recursive infra/terraform
```

## Variables reference (non-secret)

| Variable | Purpose |
|----------|---------|
| `api_domain_name` | Public API hostname |
| `api_acm_certificate_arn` | ALB TLS certificate |
| `cdn_domain_name` | Optional CloudFront alias |
| `cdn_acm_certificate_arn` | us-east-1 CDN certificate |
| `backend_image` | ECR image URI with tag |
| `descope_project_id` / `issuer` / `audience` | Auth configuration |
| `media_bucket_name` | Private S3 bucket |

Never commit `terraform.tfvars` containing tokens, DSNs, or webhook URLs.
