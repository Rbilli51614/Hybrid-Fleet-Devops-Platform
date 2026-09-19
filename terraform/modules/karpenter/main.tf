data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id              = data.aws_caller_identity.current.account_id
  partition               = data.aws_partition.current.partition
  region                  = data.aws_region.current.name
  interruption_queue_name = "${var.cluster_name}-karpenter"
}

# ---------------------------------------------------------------------------
# Node IAM role
#
# Referenced by name (not ARN) from the EC2NodeClass `spec.role` field in
# kubernetes/eks/karpenter/. Karpenter creates and manages the matching
# instance profile itself — no aws_iam_instance_profile needed here.
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

resource "aws_iam_role" "node" {
  name               = "${var.cluster_name}-karpenter-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_ssm" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "node_additional" {
  for_each = toset(var.node_iam_additional_policy_arns)

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# ---------------------------------------------------------------------------
# Spot interruption handling
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "interruption" {
  name                      = local.interruption_queue_name
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  tags = var.tags
}

data "aws_iam_policy_document" "interruption_queue" {
  statement {
    sid     = "AllowEventBridgeAndHealthEvents"
    actions = ["sqs:SendMessage"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }
    resources = [aws_sqs_queue.interruption.arn]
  }
}

resource "aws_sqs_queue_policy" "interruption" {
  queue_url = aws_sqs_queue.interruption.id
  policy    = data.aws_iam_policy_document.interruption_queue.json
}

locals {
  interruption_event_rules = {
    spot_interruption = {
      detail_type = ["EC2 Spot Instance Interruption Warning"]
      source      = ["aws.ec2"]
    }
    rebalance_recommendation = {
      detail_type = ["EC2 Instance Rebalance Recommendation"]
      source      = ["aws.ec2"]
    }
    instance_state_change = {
      detail_type = ["EC2 Instance State-change Notification"]
      source      = ["aws.ec2"]
    }
    scheduled_change = {
      detail_type = ["AWS Health Event"]
      source      = ["aws.health"]
    }
  }
}

resource "aws_cloudwatch_event_rule" "this" {
  for_each = local.interruption_event_rules

  name = "${var.cluster_name}-karpenter-${replace(each.key, "_", "-")}"

  event_pattern = jsonencode({
    "detail-type" = each.value.detail_type
    "source"      = each.value.source
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "this" {
  for_each = local.interruption_event_rules

  rule      = aws_cloudwatch_event_rule.this[each.key].name
  target_id = "karpenter-interruption-queue"
  arn       = aws_sqs_queue.interruption.arn
}

# ---------------------------------------------------------------------------
# Controller IRSA role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "controller" {
  statement {
    sid = "AllowScopedEC2InstanceActions"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "AllowScopedInstanceTermination"
    actions   = ["ec2:TerminateInstances"]
    resources = ["arn:${local.partition}:ec2:${local.region}:${local.account_id}:instance/*"]
  }

  # A real launch attempt failed outright — UnauthorizedOperation on
  # ec2:CreateTags against arn:...:launch-template/* — before it ever
  # got as far as RunInstances. Karpenter tags every resource type it
  # creates while launching a node (the launch template itself, the
  # EC2 Fleet request that actually places the instance, the instance,
  # its root volume, its ENI, and — for Spot — the spot request), not
  # just the instance, so CreateTags needs to be granted on all six,
  # not folded into AllowScopedInstanceTermination above. Scoped down
  # to Karpenter's own creation calls via the conditions below,
  # matching AWS's own reference Karpenter controller policy.
  #
  # Found one resource type at a time: the first real apply failed on
  # launch-template/*; fixing that surfaced the next failure one level
  # deeper, on fleet/* (Karpenter's CreateFleet call, which places the
  # actual RunInstances/CreateFleet request), once the launch template
  # creation itself got past the first gap.
  statement {
    sid     = "AllowScopedResourceCreationTagging"
    actions = ["ec2:CreateTags"]
    resources = [
      "arn:${local.partition}:ec2:${local.region}:${local.account_id}:instance/*",
      "arn:${local.partition}:ec2:${local.region}:${local.account_id}:volume/*",
      "arn:${local.partition}:ec2:${local.region}:${local.account_id}:network-interface/*",
      "arn:${local.partition}:ec2:${local.region}:${local.account_id}:launch-template/*",
      "arn:${local.partition}:ec2:${local.region}:${local.account_id}:spot-instances-request/*",
      "arn:${local.partition}:ec2:${local.region}:${local.account_id}:fleet/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringLike"
      variable = "ec2:CreateAction"
      values   = ["RunInstances", "CreateFleet", "CreateLaunchTemplate"]
    }
  }

  statement {
    sid = "AllowUnscopedReads"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeImages",
      "pricing:GetProducts",
      "ssm:GetParameter",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "AllowPassingNodeRole"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.node.arn]
  }

  statement {
    sid = "AllowInstanceProfileManagement"
    actions = [
      "iam:CreateInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:GetInstanceProfile",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "AllowEKSClusterRead"
    actions   = ["eks:DescribeCluster"]
    resources = ["arn:${local.partition}:eks:${local.region}:${local.account_id}:cluster/${var.cluster_name}"]
  }

  statement {
    sid = "AllowInterruptionQueueActions"
    actions = [
      "sqs:DeleteMessage",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
      "sqs:ReceiveMessage",
    ]
    resources = [aws_sqs_queue.interruption.arn]
  }
}

module "controller_irsa" {
  source = "../iam-irsa"

  role_name            = "${var.cluster_name}-karpenter-controller"
  oidc_provider_arn    = var.oidc_provider_arn
  oidc_provider_url    = var.oidc_provider_url
  namespace            = var.karpenter_namespace
  service_account_name = "karpenter"
  attach_inline_policy = true
  inline_policy_json   = data.aws_iam_policy_document.controller.json
  tags                 = var.tags
}

# ---------------------------------------------------------------------------
# Controller install
# ---------------------------------------------------------------------------

resource "helm_release" "karpenter" {
  name       = "karpenter"
  namespace  = var.karpenter_namespace
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_version

  values = [
    yamlencode({
      settings = {
        clusterName       = var.cluster_name
        clusterEndpoint   = var.cluster_endpoint
        interruptionQueue = aws_sqs_queue.interruption.name
      }
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = module.controller_irsa.role_arn
        }
      }
      nodeSelector = var.core_node_selector
      replicas     = 1
    })
  ]
}
