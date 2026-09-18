output "node_iam_role_name" {
  description = "IAM role name Karpenter assigns to the nodes it launches. Referenced by `spec.role` in EC2NodeClass manifests (see kubernetes/eks/karpenter/)."
  value       = aws_iam_role.node.name
}

output "node_iam_role_arn" {
  description = "IAM role ARN Karpenter assigns to the nodes it launches."
  value       = aws_iam_role.node.arn
}

output "controller_role_arn" {
  description = "IRSA role ARN used by the Karpenter controller."
  value       = module.controller_irsa.role_arn
}

output "interruption_queue_name" {
  description = "SQS queue name Karpenter watches for Spot interruption / rebalance / health events."
  value       = aws_sqs_queue.interruption.name
}
