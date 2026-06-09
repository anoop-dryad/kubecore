# ─────────────────────────────────────────────────────────────────────────────
# Remote state backend — S3
#
# Terraform tracks what it has created in a "state file" (terraform.tfstate).
# By default this lives on your laptop. That's fine for solo experiments but
# bad for anything real:
#   - Lose the laptop → lose state → orphan resources in AWS
#   - Can't collaborate (state can't be shared safely)
#   - No locking → two people apply at once → corrupted state
#
# A backend stores state remotely. S3 is the standard choice on AWS:
#   - Versioned bucket → history of state changes (roll back if needed)
#   - Encrypted at rest
#   - Native locking via `use_lockfile = true` (Terraform 1.10+)
#
# The chicken-and-egg problem:
#   This backend points at an S3 bucket that must already exist BEFORE this
#   code runs. Terraform can't create the bucket that holds its own state.
#   We bootstrap the bucket ONCE via AWS CLI (see README.md) and then this
#   block points at it forever.
#
# NOTE: The `key` is INTENTIONALLY ABSENT from this block.
#
# Why? We use the "partial backend configuration" pattern. Each environment
# (dev, staging, prod) has its own state file at a different key. The key
# is supplied at init time via the `-backend-config` CLI flag, set by the
# justfile recipes:
#
#   terraform init -backend-config="key=dev/kubecore"
#   terraform init -backend-config="key=staging/kubecore"
#   terraform init -backend-config="key=prod/kubecore"
#
# This gives strong isolation — switching envs requires an explicit re-init,
# not just a workspace switch. Harder to accidentally apply dev changes to
# prod.
#
# Why `use_lockfile = true` (no DynamoDB)?
#   Older Terraform required a separate DynamoDB table to prevent concurrent
#   `apply`s from corrupting state. Terraform 1.10+ has native S3 locking
#   (stored as a .tflock object next to the state file). Simpler. No extra
#   resource to manage.
#
# IMPORTANT — replace the bucket name:
#   The bucket name below must match what you created during bootstrap.
#   It includes your AWS account ID so it's globally unique.
#   Find your account ID with: `aws sts get-caller-identity --query Account`
#
# Docs:
#   https://developer.hashicorp.com/terraform/language/backend/s3
#   https://developer.hashicorp.com/terraform/language/state/workspaces
# ─────────────────────────────────────────────────────────────────────────────


terraform {
  backend "s3" {

    # S3 bucket holding all state files. Created once via bootstrap CLI.
    # Replace <ACCOUNT_ID> with your AWS account ID.
    bucket = "kubecore-tfstate-363160363950"

    # Region of the state bucket (NOT necessarily where resources live —
    # though we use the same region for both to keep it simple).
    # Inside backend "s3" {}, you must use literal values only: no var.region allowed
    region = "eu-central-1"

    # Native S3 locking. Requires Terraform 1.10+.
    # Without this, two simultaneous `apply`s could corrupt state.
    use_lockfile = true

    # Encrypt state at rest with SSE-S3 (the bucket itself is also encrypted).
    encrypt = true

    # Subdirectory prefix for non-default workspaces. The `default`
    # workspace is unaffected by this prefix.
    workspace_key_prefix = "workspaces"

    # NOTE: `key` is supplied at init time via -backend-config
    # See justfile for the pattern.


  }
}
