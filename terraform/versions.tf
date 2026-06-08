# ─────────────────────────────────────────────────────────────────────────────
# Terraform & provider version constraints
#
# This file defines the minimum Terraform CLI version and which providers
# (with which versions) this configuration depends on.
#
# Why a separate file?
#   Terraform merges all *.tf files in this directory at parse time. Splitting
#   `terraform {}` configuration from resources / modules / providers keeps
#   each file focused on one concern. Easy to find "what version are we on?"
#   without scrolling through 500 lines of module composition.
#
# About the `terraform {}` block:
#   This is Terraform's special configuration block (not a resource).
#   Across all .tf files in this directory, you can have only ONE of each:
#     - `required_version`
#     - `required_providers`
#     - `backend "..." {}`   (lives in backend.tf in our case)
#
# Version constraint syntax (`~>` operator):
#   `~> 5.80`  →  allows >= 5.80.0 and < 6.0.0  (latest 5.x minor/patch)
#   `~> 5.80.0` → allows >= 5.80.0 and < 5.81.0 (latest patch only)
#   `>= 5.0`   →  any version 5.0 or higher (no upper bound — risky)
#   We use `~>` to get bug fixes automatically but avoid breaking major upgrades.
#
# Why pin providers at all?
#   Without pinning, a new provider release could change behavior overnight
#   and break your applies. Pinning makes builds reproducible.
#
# Adding a new provider later (e.g. kubernetes, helm, awscc):
#   Just add another entry to required_providers and run `terraform init`.
#
# Docs:
#   https://developer.hashicorp.com/terraform/language/providers/requirements
#   https://developer.hashicorp.com/terraform/language/expressions/version-constraints
# ─────────────────────────────────────────────────────────────────────────────

terraform {

  # Minimum Terraform CLI version. 1.10+ is needed for S3 backend's
  # `use_lockfile = true` feature (replaces the separate DynamoDB lock table).
  required_version = ">=1.12"

  required_providers {
    # AWS provider — the main one. Used by every AWS resource.
    # https://registry.terraform.io/providers/hashicorp/aws/latest/docs
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # Add more providers here as needed. Examples:
    #
    # kubernetes = {
    #   source  = "hashicorp/kubernetes"
    #   version = "~> 2.30"
    # }
    #
    # helm = {
    #   source  = "hashicorp/helm"
    #   version = "~> 2.15"
    # }
  }

}
