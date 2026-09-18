output "security_group_id" {
  description = "ID of the shared security group attached to every VM-tier node."
  value       = aws_security_group.nodes.id
}

output "node_role_arns" {
  description = "Map of node group key to its IAM role ARN."
  value       = { for k, v in aws_iam_role.node : k => v.arn }
}

output "autoscaling_group_names" {
  description = "Map of node group key to its Auto Scaling Group name."
  value       = { for k, v in aws_autoscaling_group.node : k => v.name }
}

output "join_token_ssm_path" {
  description = "SSM Parameter Store path used to exchange the kubeadm join command between control-plane and worker nodes."
  value       = local.join_token_ssm_path
}

output "ssm_transfer_bucket_name" {
  description = "S3 bucket for the Ansible aws_ssm connection plugin's file transfer staging. Export as ANSIBLE_SSM_BUCKET before running the bootstrap playbook — see ansible/README.md."
  value       = aws_s3_bucket.ssm_transfer.bucket
}
