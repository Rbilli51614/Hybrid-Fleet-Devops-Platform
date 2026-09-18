include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  # Local relative path for now; switch to the tagged git source once
  # modules/vpc has a release tag (see terraform/modules/vpc/README.md).
  source = "../../../modules/vpc"
}

inputs = {
  name       = "hybrid-fleet-onprem"
  cidr_block = "10.1.0.0/16" # non-overlapping with cloud-vpc's 10.0.0.0/16 — see docs/architecture.md
  azs        = ["us-east-1a", "us-east-1b"]

  public_subnet_cidrs  = ["10.1.0.0/24", "10.1.1.0/24"]
  private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24"]

  # Small/persistent VM fleet, not autoscaled traffic — one shared NAT is
  # plenty and keeps cost down.
  single_nat_gateway = true

  # No eks_cluster_name: this VPC hosts the self-managed kubeadm/k3s tier,
  # not EKS, so none of the Karpenter/ALB discovery tags apply here.

  tags = {
    Tier = "onprem"
  }
}
