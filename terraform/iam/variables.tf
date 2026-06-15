# ─────────────────────────────────────────────────────────────────────────────
# IAM module input variables
# ─────────────────────────────────────────────────────────────────────────────

variable "environment" {
  description = "Environment name (dev, staging, prod). Used in resource naming."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name. Used for naming IAM roles."
  type        = string
}
