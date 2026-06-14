# ─────────────────────────────────────────────────────────────────────────────
# VPC module input variables
#
# These are the "knobs" callers (the root main.tf) tune to customize the VPC.
# All have descriptions so `terraform plan` output is self-documenting.
#
# Validation blocks catch obvious mistakes at plan time rather than apply time —
# fail fast on bad input.
# ─────────────────────────────────────────────────────────────────────────────

variable "environment" {
  description = "Environment name (dev, staging, prod). Used in resource naming."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name. Used for naming resources and EKS auto-discovery tags."
  type        = string
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC. /16 gives 65,536 IPs — plenty for any realistic workload."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    # Ensure CIDR is in the RFC1918 private space — public CIDRs would conflict with internet routing
    condition     = can(cidrsubnet(var.vpc_cidr_block, 0, 0))
    error_message = "vpc_cidr_block must be a valid CIDR notation (e.g. 10.0.0.0/16)."
  }
}

variable "azs" {
  description = "Availability zones to deploy subnets into. EKS requires at least 2."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "EKS requires at least 2 availability zones."
  }
}

variable "public_subnets" {
  description = "CIDR blocks for public subnets, one per AZ. Order must match azs."
  type        = list(string)

  validation {
    condition     = length(var.public_subnets) >= 2
    error_message = "At least 2 public subnets required for EKS load balancers."
  }
}

variable "private_subnets" {
  description = "CIDR blocks for private subnets, one per AZ. Order must match azs."
  type        = list(string)

  validation {
    condition     = length(var.private_subnets) >= 2
    error_message = "At least 2 private subnets required for EKS worker high availability."
  }
}
