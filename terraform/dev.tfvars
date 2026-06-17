# Variable values for the `dev` environment.
# Loaded by: `just tf-plan-dev`, `just tf-apply-dev`, etc.

environment  = "dev"
region       = "eu-central-1"
cluster_name = "kubecore"

# ─── VPC ─────────────────────────────────────────────────────────────────────

vpc_cidr_block = "10.0.0.0/16"

# 2 AZs (EKS minimum). Frankfurt has 3; we use 2 for cost-conscious dev.
azs = ["eu-central-1a", "eu-central-1b"]

# Public subnets get auto-assigned public IPs. Used for ALBs and (future) NAT.
public_subnets = [
  "10.0.1.0/24", # eu-central-1a — 251 usable IPs
  "10.0.2.0/24", # eu-central-1b — 251 usable IPs
]

# Private subnets — no public IPs, no internet route (yet). For EKS workers.
private_subnets = [
  "10.0.11.0/24", # eu-central-1a
  "10.0.12.0/24", # eu-central-1b
]
