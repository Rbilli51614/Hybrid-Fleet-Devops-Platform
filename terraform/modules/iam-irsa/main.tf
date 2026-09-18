data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = var.tags
}

# count, not for_each: toset(var.policy_arns) needs every element's VALUE
# known at plan time to compute set membership, and it breaks the same way
# attach_inline_policy was built to avoid (see variables.tf) the moment a
# caller passes a same-apply resource's ARN — alb-ingress-controller does,
# with policy_arns = [aws_iam_policy.controller.arn]. count only needs the
# list's LENGTH known, not its elements' values, so it tolerates this fine.
resource "aws_iam_role_policy_attachment" "managed" {
  count = length(var.policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = var.policy_arns[count.index]
}

resource "aws_iam_role_policy" "inline" {
  count = var.attach_inline_policy ? 1 : 0

  name   = "${var.role_name}-inline"
  role   = aws_iam_role.this.id
  policy = var.inline_policy_json
}
