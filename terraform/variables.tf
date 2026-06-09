# ─────────────────────────────────────────────────────────────────────────────
# Input variables
#
# Values for these come from <env>.tfvars files. The justfile passes the
# right tfvars file per environment via `-var-file=<env>.tfvars`.
#
# No defaults on env-specific variables — we want errors if a tfvars file
# is missing values, not silent defaults that mask problems.
# ─────────────────────────────────────────────────────────────────────────────

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "eu-central-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}
