variable "name" {
  description = "Name used for the VPC, the cluster and the IAM roles."
  type        = string
  default     = "platform"
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-central-1"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version. Upgrade one minor version at a time."
  type        = string
  default     = "1.33"
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "github_repository" {
  description = "Repository allowed to assume the CI roles, as owner/name."
  type        = string
}

variable "apply_policy_arns" {
  description = "Policies attached to the role that applies this stack from main. Narrow these for real use."
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
}

variable "cluster_admin_role_arns" {
  description = "IAM roles (for example SSO permission-set roles) that get cluster-admin through EKS access entries."
  type        = map(string)
  default     = {}
}

variable "bootstrap_public_endpoint" {
  description = <<-EOT
    Only for the first apply of a brand-new cluster. Opens the public API endpoint
    to bootstrap_cidrs so an operator can install the in-cluster runners. Set back
    to false as soon as the runners are registered.
  EOT
  type        = bool
  default     = false
}

variable "bootstrap_cidrs" {
  description = "CIDRs allowed to reach the public endpoint while bootstrap_public_endpoint is true."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.bootstrap_cidrs : c != "0.0.0.0/0"])
    error_message = "Do not open the API endpoint to the whole internet, even during bootstrap."
  }

  validation {
    condition     = !var.bootstrap_public_endpoint || length(var.bootstrap_cidrs) > 0
    error_message = "bootstrap_public_endpoint needs at least one CIDR in bootstrap_cidrs."
  }
}
