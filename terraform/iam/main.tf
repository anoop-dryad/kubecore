# ─────────────────────────────────────────────────────────────────────────────
# IAM Module — Roles for the EKS platform
#
# What this creates (all FREE):
#   - EKS cluster role: assumed by the EKS service to manage the control plane
#   - EKS node role:    assumed by EC2 worker nodes; permissions to run as
#                       Kubernetes nodes (pull images, write logs, etc.)
#
# IAM is free. Roles cost nothing to define; they only have effect when
# something assumes them. We can create EKS-related roles today even though
# no EKS cluster exists yet — when we add EKS, it'll reference these.
#
# Why two roles?
#   - The cluster role is for AWS itself (the EKS managed service)
#   - The node role is for the EC2 instances running as workers
#   They have completely different permissions and trust policies.
#
# Trust policies vs permission policies:
#   - Trust policy = WHO can assume this role (the "Principal")
#   - Permission policy = WHAT the role can do once assumed
#
# AWS-managed policies vs custom:
#   AWS publishes standard policies for EKS (e.g. AmazonEKSClusterPolicy).
#   We attach those rather than writing our own — fewer mistakes, AWS keeps
#   them updated as EKS evolves.
#
# Docs:
#   https://docs.aws.amazon.com/eks/latest/userguide/service_IAM_role.html
#   https://docs.aws.amazon.com/eks/latest/userguide/create-node-role.html
# ─────────────────────────────────────────────────────────────────────────────

# ─── Locals ──────────────────────────────────────────────────────────────────

locals {
  name_prefix = "${var.environment}-${var.cluster_name}"
}

# ─── EKS Cluster Role ────────────────────────────────────────────────────────
# Assumed by the EKS service (eks.amazonaws.com). This is what allows AWS
# to manage your cluster on your behalf — provision the control plane,
# manage networking, communicate with nodes.

# Trust policy: only the EKS service can assume this role
data "aws_iam_policy_document" "eks_cluster_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "${local.name_prefix}-eks-cluster-role"
  description        = "EKS control plane role for ${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume_role.json

  tags = {
    Name = "${local.name_prefix}-eks-cluster-role"
  }
}

# Standard AWS-managed policy granting the EKS control plane the permissions
# it needs (manage ENIs, security groups, load balancers, etc.)
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ─── EKS Node Role ───────────────────────────────────────────────────────────
# Attached to the EC2 instances running as Kubernetes worker nodes. Lets
# kubelet/kube-proxy register with the cluster, pull images, etc.

# Trust policy: only EC2 instances can assume this role (via instance profile)
data "aws_iam_policy_document" "eks_node_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_node" {
  name               = "${local.name_prefix}-eks-node-role"
  description        = "EKS worker node role for ${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume_role.json

  tags = {
    Name = "${local.name_prefix}-eks-node-role"
  }
}

# The three standard policies every EKS worker node needs:

# 1. AmazonEKSWorkerNodePolicy — basic permissions to run as a Kubernetes node
resource "aws_iam_role_policy_attachment" "eks_node_worker_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# 2. AmazonEKS_CNI_Policy — for the VPC CNI plugin (manages pod networking)
resource "aws_iam_role_policy_attachment" "eks_node_cni_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# 3. AmazonEC2ContainerRegistryReadOnly — to pull images from ECR
resource "aws_iam_role_policy_attachment" "eks_node_ecr_read_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
