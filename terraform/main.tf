locals {
  workspace = terraform.workspace == "default" ? var.environment : terraform.workspace
}

module "vpc" {
  source = "./vpc"

  environment     = var.environment
  cluster_name    = var.cluster_name
  vpc_cidr_block  = var.vpc_cidr_block
  azs             = var.azs
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets
}

# ─── IAM ─────────────────────────────────────────────────────────────────────
# EKS-related IAM roles. Created now (free) so future EKS module can reference
# them without changes.

module "iam" {
  source = "./iam"

  environment  = var.environment
  cluster_name = var.cluster_name
}
