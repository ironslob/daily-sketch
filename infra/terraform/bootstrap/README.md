# Terraform state bootstrap

One-time setup for remote Terraform state. Run this **before** applying `envs/staging` or `envs/production`.

## What it creates

- Private, versioned, encrypted S3 bucket for Terraform state
- DynamoDB table for state locking
- Bucket policy denying non-TLS access

## Prerequisites

- AWS CLI configured with permissions to create S3 and DynamoDB resources
- Terraform >= 1.5

## Steps

```bash
cd infra/terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — state_bucket_name must be globally unique.

terraform init
terraform plan
terraform apply
```

Copy the `backend_config_snippet` output into each environment's `backend.tf`, replacing `ENVIRONMENT` with `staging` or `production`.

## Notes

- Bootstrap uses **local state** intentionally. Store the generated `terraform.tfstate` securely (e.g. encrypted backup); losing it complicates bucket lifecycle changes.
- Do **not** store application secrets in this module.
- After bootstrap, run `terraform init -migrate-state` inside each env directory when wiring the S3 backend for the first time.
