# ─────────────────────────────────────────────────────────────────────────────
# VPC Module — Networking foundation for the kubecore platform
#
# What this creates (all FREE — no NAT yet):
#   - 1 VPC with /16 address space
#   - 2 Public subnets  (1 per AZ) — for load balancers + future NAT
#   - 2 Private subnets (1 per AZ) — for EKS worker nodes (when added)
#   - 1 Internet Gateway
#   - 1 Public route table (→ Internet via IGW)
#   - 1 Private route table (local routes only — no internet yet)
#   - 4 Route table associations (linking subnets to route tables)
#   - 2 Security Groups (EKS cluster + worker, even though EKS not built yet)
#
# What this does NOT create yet (intentional — costs money):
#   - NAT Gateway (~$32/month) — add later when EKS workloads need outbound
#   - Elastic IP (the NAT's public IP — also added later)
#
# Total cost: $0/month while running.
#
# EKS auto-discovery tags:
#   EKS uses tag conventions to find which subnets to use for load balancers:
#     - kubernetes.io/cluster/<cluster-name> = "shared" → marks VPC/subnets as
#       belonging to this cluster
#     - kubernetes.io/role/elb = "1" → public subnets for internet-facing LBs
#     - kubernetes.io/role/internal-elb = "1" → private subnets for internal LBs
#   We add these tags now so the future EKS module "just works."
#
# Why no NACLs explicitly:
#   AWS's default NACL is wide-open (allow all). Adding our own would just
#   replicate the default. Security Groups (which we DO configure) provide
#   the meaningful access control.
#
# Docs:
#   https://docs.aws.amazon.com/eks/latest/userguide/network-reqs.html
#   https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc
# ─────────────────────────────────────────────────────────────────────────────

# ─── Locals ──────────────────────────────────────────────────────────────────

locals {
  # The "Name" prefix for all AWS resources in this module.
  # Example: "dev-kubecore" → "dev-kubecore-vpc", "dev-kubecore-public-1a", etc.
  name_prefix = "${var.environment}-${var.cluster_name}"

  # EKS cluster discovery tag — applied to VPC and all subnets.
  # "shared" means multiple clusters can use these resources; "owned" means
  # this cluster is the exclusive owner (used when EKS auto-creates infra).
  eks_cluster_tag = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# ─── VPC ─────────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr_block

  # Required for EKS:
  enable_dns_hostnames = true # instances get DNS names like ip-10-0-1-5.eu-central-1.compute.internal
  enable_dns_support   = true # internal DNS resolution works inside the VPC

  tags = merge(
    local.eks_cluster_tag,
    {
      Name = "${local.name_prefix}-vpc"
    }
  )
}

# ─── Internet Gateway ────────────────────────────────────────────────────────
# Provides the public subnets with a route to the internet.
# Free, one per VPC.

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

# ─── Public Subnets ──────────────────────────────────────────────────────────
# One per AZ. Used by:
#   - Internet-facing load balancers
#   - NAT Gateway (when we add it later)
#   - Anything that needs a public IP
#
# `map_public_ip_on_launch = true` means EC2 instances launched in this subnet
# automatically get a public IP. For EKS, we typically DON'T put nodes here
# (we use private subnets) but the auto-assign convenience is standard for
# public subnets.
#
# The `count = length(...)` pattern creates one subnet per CIDR in the list.
# Access them as aws_subnet.public[0], aws_subnet.public[1], etc.

resource "aws_subnet" "public" {
  count = length(var.public_subnets)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    local.eks_cluster_tag,
    {
      Name                     = "${local.name_prefix}-public-${var.azs[count.index]}"
      "kubernetes.io/role/elb" = "1" # EKS uses this tag to find subnets for public LBs
      Tier                     = "public"
    }
  )
}

# ─── Private Subnets ─────────────────────────────────────────────────────────
# One per AZ. Used by:
#   - EKS worker nodes (when EKS is added)
#   - RDS instances
#   - Anything that should NOT be directly reachable from the internet
#
# Currently these have NO route to the internet (no NAT yet). Resources here
# can talk to each other and to AWS services via VPC endpoints (if added),
# but cannot reach the public internet. That's fine for now.

resource "aws_subnet" "private" {
  count = length(var.private_subnets)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(
    local.eks_cluster_tag,
    {
      Name                              = "${local.name_prefix}-private-${var.azs[count.index]}"
      "kubernetes.io/role/internal-elb" = "1" # EKS uses this for internal-only LBs
      Tier                              = "private"
    }
  )
}

# ─── Public Route Table ──────────────────────────────────────────────────────
# Routes for public subnets:
#   - local: traffic within VPC stays in VPC (added automatically by AWS)
#   - 0.0.0.0/0 → Internet Gateway: everything else goes to the internet

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ─── Private Route Table ─────────────────────────────────────────────────────
# Routes for private subnets:
#   - local: traffic within VPC stays in VPC (added automatically)
#   - No internet route YET — will add `0.0.0.0/0 → NAT Gateway` when we
#     enable NAT later. For now, private subnets can only reach within the VPC.
#
# Empty route block means just the local route (which AWS adds automatically).

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  # Future: NAT Gateway route goes here
  # route {
  #   cidr_block     = "0.0.0.0/0"
  #   nat_gateway_id = aws_nat_gateway.main.id
  # }

  tags = {
    Name = "${local.name_prefix}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ─── EKS Cluster Security Group ──────────────────────────────────────────────
# Controls traffic to/from the EKS control plane (managed by AWS but lives
# in our VPC). Even though EKS doesn't exist yet, defining this now means
# the future EKS module can reference it cleanly.

resource "aws_security_group" "eks_cluster" {
  name        = "${local.name_prefix}-eks-cluster-sg"
  description = "Security group for EKS control plane"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-eks-cluster-sg"
  }
}

# Cluster SG: allow all egress (control plane needs to reach worker nodes)
resource "aws_vpc_security_group_egress_rule" "eks_cluster_all_egress" {
  security_group_id = aws_security_group.eks_cluster.id
  description       = "Allow EKS cluster all outbound traffic"
  ip_protocol       = "-1" # -1 = all protocols
  cidr_ipv4         = "0.0.0.0/0"
}

# ─── EKS Worker Security Group ───────────────────────────────────────────────
# Attached to all EKS worker nodes. EKS dynamically adds ingress rules as
# you create LoadBalancer services — that's why we use `lifecycle.ignore_changes`
# on ingress.

resource "aws_security_group" "eks_worker" {
  name        = "${local.name_prefix}-eks-worker-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-eks-worker-sg"
  }

  lifecycle {
    # EKS auto-injects ingress rules when LoadBalancer services are created.
    # If Terraform tries to "correct" these on next apply, things break.
    # Telling Terraform to leave ingress alone keeps EKS happy.
    ignore_changes = [ingress]
  }
}

# Worker SG: allow all egress (workers need to pull images, call APIs, etc.)
resource "aws_vpc_security_group_egress_rule" "eks_worker_all_egress" {
  security_group_id = aws_security_group.eks_worker.id
  description       = "Allow worker nodes all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ─── Cross-SG Rules ──────────────────────────────────────────────────────────
# These rules use `referenced_security_group_id` instead of CIDR — safer
# because they only allow traffic from resources in the specified SG, not
# from any IP that happens to be in a CIDR range.

# Worker → Cluster: workers must reach the EKS API server on 443
resource "aws_vpc_security_group_ingress_rule" "cluster_from_workers" {
  security_group_id            = aws_security_group.eks_cluster.id
  description                  = "Allow worker nodes to reach EKS API server"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.eks_worker.id
}

# Cluster → Worker: control plane sends to kubelet on 10250 (and webhooks)
resource "aws_vpc_security_group_ingress_rule" "workers_from_cluster" {
  security_group_id            = aws_security_group.eks_worker.id
  description                  = "Allow EKS control plane to reach kubelet on workers"
  from_port                    = 1025
  to_port                      = 65535
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.eks_cluster.id
}

# Worker ↔ Worker: pods on different nodes need to talk to each other.
# `self = true` would be ideal but the new SG rule resources don't support
# it — instead we reference the worker SG from itself.
resource "aws_vpc_security_group_ingress_rule" "workers_from_workers" {
  security_group_id            = aws_security_group.eks_worker.id
  description                  = "Allow worker-to-worker communication"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.eks_worker.id
}
