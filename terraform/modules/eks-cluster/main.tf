locals {
  core_node_subnet_ids = length(var.core_node_subnet_ids) > 0 ? var.core_node_subnet_ids : var.subnet_ids
}

# ---------------------------------------------------------------------------
# Cluster IAM role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.cluster_name}-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_public_access  = var.endpoint_public_access
    endpoint_private_access = true
    public_access_cidrs     = var.endpoint_public_access_cidrs
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  tags = merge(var.tags, {
    Name = var.cluster_name
  })

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

resource "aws_eks_access_entry" "admins" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
}

resource "aws_eks_access_policy_association" "admins" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admins]
}

# Lets Karpenter's EC2NodeClass securityGroupSelectorTerms find the
# cluster-managed security group by tag instead of a hardcoded ID.
resource "aws_ec2_tag" "cluster_security_group_karpenter_discovery" {
  resource_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}

# ---------------------------------------------------------------------------
# OIDC provider (IRSA)
# ---------------------------------------------------------------------------

data "tls_certificate" "cluster" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Core system managed node group
#
# Hosts kube-system components (CoreDNS, EBS CSI, and — from Phase 1's
# consumer, terraform/live/dev/karpenter — the Karpenter controller itself)
# that must be running before Karpenter can provision any further capacity.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "core_node" {
  name               = "${var.cluster_name}-core-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "core_node_worker" {
  role       = aws_iam_role.core_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "core_node_cni" {
  role       = aws_iam_role.core_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "core_node_ecr" {
  role       = aws_iam_role.core_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "core_node_ssm" {
  role       = aws_iam_role.core_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_eks_node_group" "core" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "core-system"
  node_role_arn   = aws_iam_role.core_node.arn
  subnet_ids      = local.core_node_subnet_ids

  instance_types = var.core_node_instance_types
  ami_type       = var.core_node_ami_type
  capacity_type  = "ON_DEMAND"

  scaling_config {
    desired_size = var.core_node_desired_size
    min_size     = var.core_node_min_size
    max_size     = var.core_node_max_size
  }

  labels = {
    "role" = "system-core"
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.core_node_worker,
    aws_iam_role_policy_attachment.core_node_cni,
    aws_iam_role_policy_attachment.core_node_ecr,
    aws_iam_role_policy_attachment.core_node_ssm,
  ]
}

# ---------------------------------------------------------------------------
# Managed addons
# ---------------------------------------------------------------------------

# aws-ebs-csi-driver is the one addon here that actually calls AWS APIs
# (EC2/EBS) on its own behalf, so — unlike vpc-cni/coredns/kube-proxy — it
# needs real IAM permissions, via IRSA like every other AWS-calling
# controller in this repo. Without this, its controller pods have no
# credentials path at all (not even IMDS node-role fallback in practice)
# and sit in CrashLoopBackOff: "no EC2 IMDS role found" — caught on a real
# apply, not something `terraform validate` or a mocked plan could surface.
module "ebs_csi_irsa" {
  source = "../iam-irsa"

  role_name            = "${var.cluster_name}-ebs-csi-driver"
  oidc_provider_arn    = aws_iam_openid_connect_provider.cluster.arn
  oidc_provider_url    = replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
  namespace            = "kube-system"
  service_account_name = "ebs-csi-controller-sa"
  policy_arns          = ["arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]
  tags                 = var.tags
}

resource "aws_eks_addon" "this" {
  for_each = var.cluster_addons

  cluster_name  = aws_eks_cluster.this.name
  addon_name    = each.key
  addon_version = each.value.version

  service_account_role_arn = each.key == "aws-ebs-csi-driver" ? module.ebs_csi_irsa.role_arn : null

  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags

  depends_on = [aws_eks_node_group.core]
}
