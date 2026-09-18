variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes minor version for the control plane (e.g. \"1.30\")."
  type        = string
  default     = "1.30"
}

variable "vpc_id" {
  description = "VPC the cluster and its core node group are deployed into."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the EKS control plane ENIs. Should span at least 2 AZs; private subnets are recommended so the control plane ENIs aren't internet-facing."
  type        = list(string)
}

variable "core_node_subnet_ids" {
  description = "Subnets for the core system managed node group. Defaults to var.subnet_ids if not set."
  type        = list(string)
  default     = []
}

variable "endpoint_public_access" {
  description = "Whether the EKS API server endpoint is reachable from the public internet. Kept true by default for a portfolio project's kubectl/CI access without a bastion/VPN hop; set false and rely on the VPN link for anything closer to production."
  type        = bool
  default     = true
}

variable "endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public API endpoint, when enabled."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "admin_principal_arns" {
  description = "Additional IAM principal ARNs (users/roles) granted EKS cluster-admin via access entries, beyond the principal that creates the cluster."
  type        = list(string)
  default     = []
}

variable "core_node_instance_types" {
  description = "Instance types for the core system node group, which hosts kube-system components (CoreDNS, EBS CSI, Karpenter controller) that must exist before Karpenter can provision any other capacity."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "core_node_desired_size" {
  description = "Desired node count for the core system node group."
  type        = number
  default     = 2
}

variable "core_node_min_size" {
  description = "Minimum node count for the core system node group."
  type        = number
  default     = 2
}

variable "core_node_max_size" {
  description = "Maximum node count for the core system node group."
  type        = number
  default     = 3
}

variable "cluster_addons" {
  description = "EKS-managed addons to install, by name, with an optional version override (null = latest compatible)."
  type = map(object({
    version = optional(string)
  }))
  default = {
    "vpc-cni"            = {}
    "coredns"            = {}
    "kube-proxy"         = {}
    "aws-ebs-csi-driver" = {}
  }
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
