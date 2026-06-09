# ─────────────────────────────────────────────────────────────────────────────
# Provider configuration
#
# `required_providers` (in versions.tf) declares WHICH providers we need.
# This file CONFIGURES them — region, authentication, default behaviors.
#
# Authentication:
#   The AWS provider finds credentials automatically from one of:
#     1. Environment variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
#     2. Shared credentials file: ~/.aws/credentials (set via `aws configure`)
#     3. IAM role (when running on EC2/ECS/EKS with an instance profile)
#     4. SSO / assume-role chains
#   For local development we use option 2 (set up via `aws configure`).
#
# Why `default_tags`?
#   Every AWS resource this provider creates will automatically have these
#   tags applied. Saves repeating `tags = {...}` on every resource block,
#   AND makes it trivial to:
#     - Identify Terraform-managed resources (`ManagedBy = "terraform"`)
#     - Filter AWS Cost Explorer by Project
#     - Know which workspace created a given resource (debug + audit)
#   Resources can still add their own tags — they merge with these defaults.
#
# Configures HOW providers behave (region, default tags). The WHICH (versions)
# is in versions.tf.
# Tag every resource with `Environment` for cost tracking and audit.
#
# About `provider` aliases:
#   You can configure the same provider multiple times with different settings
#   using `alias = "..."`. Useful for multi-region or multi-account setups.
#   We don't need this yet (single account, single region).
#
# Docs:
#   https://registry.terraform.io/providers/hashicorp/aws/latest/docs
#   https://developer.hashicorp.com/terraform/language/providers/configuration
# ─────────────────────────────────────────────────────────────────────────────

provider "aws" {

  # Region where all AWS resources will live (override per-resource if needed).
  region = var.region

  # Tags applied to every taggable resource created by this provider.
  # These can be overridden or extended per-resource via the `tags` argument.
  default_tags {
    tags = {
      Project     = "kubecore"
      Owner       = "terraform"
      Origin      = "kubecore" # repo name — helps trace "where did this come from"
      Environment = var.environment
    }
  }

}


# ─── Example: second provider for multi-account (commented out) ──────────────
# When you eventually need to deploy to a second account (e.g. shared services),
# add an aliased provider like this and use `providers = { aws.shared = aws.shared }`
# in module blocks.
#
# provider "aws" {
#   alias  = "shared"
#   region = var.region
#
#   assume_role {
#     role_arn     = "arn:aws:iam::<SHARED_ACCOUNT_ID>:role/Terraform"
#     session_name = "Terraform"
#   }
#
#   default_tags {
#     tags = {
#       Project   = "kubecore"
#       ManagedBy = "terraform"
#       Account   = "shared"
#     }
#   }
# }
