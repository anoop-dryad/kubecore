# ─────────────────────────────────────────────────────────────────────────────
# IAM module outputs
#
# Consumed by the future EKS module — when we add it, the cluster will
# reference eks_cluster_role_arn and the node group will reference
# eks_node_role_arn.
# ─────────────────────────────────────────────────────────────────────────────

output "eks_cluster_role_arn" {
  description = "ARN of the IAM role assumed by the EKS control plane"
  value       = aws_iam_role.eks_cluster.arn
}

output "eks_cluster_role_name" {
  description = "Name of the IAM role assumed by the EKS control plane"
  value       = aws_iam_role.eks_cluster.name
}

output "eks_node_role_arn" {
  description = "ARN of the IAM role assumed by EKS worker nodes"
  value       = aws_iam_role.eks_node.arn
}

output "eks_node_role_name" {
  description = "Name of the IAM role assumed by EKS worker nodes"
  value       = aws_iam_role.eks_node.name
}
