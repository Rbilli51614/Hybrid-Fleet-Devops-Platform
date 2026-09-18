variable "name" {
  description = "Name prefix for all resources created by this module."
  type        = string
}

variable "cluster_name" {
  description = "Logical name for the self-managed Kubernetes cluster these node groups form. Used to tag instances and to scope the SSM Parameter Store path the kubeadm join command is exchanged through."
  type        = string
}

variable "vpc_id" {
  description = "VPC the node groups are deployed into (the \"on-prem\" VPC, not the cloud/EKS one)."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the node groups. No public IPs are assigned — access is SSM Session Manager only, never a public/SSH path."
  type        = list(string)
}

variable "ami_ssm_parameter" {
  description = "SSM Parameter Store path resolving to the AMI ID to launch. Defaults to the latest published Ubuntu 22.04 LTS AMI, avoiding a hardcoded/stale regional AMI ID."
  type        = string
  default     = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

variable "node_groups" {
  description = <<-EOT
    Node groups to create, keyed by an arbitrary name (e.g. "control-plane", "worker"). Each becomes its own launch template + Auto Scaling Group.
    `role` is written as the `Role` tag on every instance and is what the Ansible dynamic inventory (ansible/inventories/dev/aws_ec2.yml) groups hosts by — it must be exactly "control-plane" or "worker" for the bootstrap playbook's group_vars to apply correctly.
  EOT
  type = map(object({
    role                = string
    instance_type       = string
    desired_size        = number
    min_size            = number
    max_size            = number
    root_volume_size_gb = optional(number, 50)
  }))
}

variable "join_token_ssm_path" {
  description = "SSM Parameter Store path the control-plane node writes the kubeadm join command to and worker nodes read it from (see ansible/roles/k8s-control-plane and k8s-worker). Terraform only grants IAM access to this path; the parameter itself is managed by Ansible, not Terraform."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
