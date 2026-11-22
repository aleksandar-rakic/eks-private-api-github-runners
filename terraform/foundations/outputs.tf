output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "public_endpoint_enabled" {
  description = "Should be false outside the bootstrap window."
  value       = var.bootstrap_public_endpoint
}

output "plan_role_arn" {
  value = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  value = aws_iam_role.apply.arn
}

# Inputs for stacks that build on this one (add-ons, workload roles).

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnets
}

output "node_security_group_id" {
  description = "Security group of the managed nodes, for rules that let in-VPC clients reach pods."
  value       = module.eks.node_security_group_id
}

output "cluster_oidc_provider_arn" {
  description = "IAM OIDC provider of the cluster, for IAM roles for service accounts."
  value       = module.eks.oidc_provider_arn
}
