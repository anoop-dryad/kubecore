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
