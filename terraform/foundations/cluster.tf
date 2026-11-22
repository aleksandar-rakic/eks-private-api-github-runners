module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.37"

  cluster_name    = var.name
  cluster_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # The API is private. The public endpoint exists only during bootstrap,
  # and only for the CIDRs listed in bootstrap_cidrs.
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access       = var.bootstrap_public_endpoint
  cluster_endpoint_public_access_cidrs = var.bootstrap_cidrs

  # Access entries only; no aws-auth ConfigMap and no implicit admin for whoever ran apply.
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = false

  access_entries = {
    for key, arn in var.cluster_admin_role_arns : key => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  cluster_addons = {
    vpc-cni                = { before_compute = true }
    coredns                = {}
    kube-proxy             = {}
    eks-pod-identity-agent = {}
  }

  eks_managed_node_groups = {
    system = {
      ami_type       = "AL2023_ARM_64_STANDARD"
      instance_types = ["m7g.large"]
      min_size       = 2
      max_size       = 4
      desired_size   = 2

      metadata_options = {
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
      }
    }
  }
}
