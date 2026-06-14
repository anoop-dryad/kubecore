# ─────────────────────────────────────────────────────────────────────────────
# VPC module outputs
#
# These are the values other modules can consume. The future EKS module will
# pull subnet IDs and security group IDs from here. The root main.tf can also
# re-export these for app repos to use via terraform_remote_state.
#
# Naming convention: output names match what consuming modules will expect.
# Changing an output name is a breaking change for any consumer.
# ─────────────────────────────────────────────────────────────────────────────

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (for load balancers, future NAT)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (for EKS worker nodes, RDS)"
  value       = aws_subnet.private[*].id
}

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "ID of the private route table (will need NAT route added later)"
  value       = aws_route_table.private.id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "eks_cluster_sg_id" {
  description = "Security group ID for the EKS control plane"
  value       = aws_security_group.eks_cluster.id
}

output "eks_worker_sg_id" {
  description = "Security group ID for EKS worker nodes"
  value       = aws_security_group.eks_worker.id
}

output "availability_zones" {
  description = "List of AZs the subnets span"
  value       = var.azs
}
