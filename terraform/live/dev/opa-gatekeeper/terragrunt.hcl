include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "eks_controller" {
  path = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/eks-controller.hcl"
}

terraform {
  source = "git::https://github.com/Rbilli51614/Hybrid-Fleet-Devops-Platform.git//terraform/modules/opa-gatekeeper?ref=modules/opa-gatekeeper/v1.0.0"
}

inputs = {}
