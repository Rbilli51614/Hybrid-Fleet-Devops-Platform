variable "aws_region" {
  description = "AWS region hosting the Terraform state backend."
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Globally-unique S3 bucket name for Terraform remote state. Must be set explicitly (S3 bucket names are global)."
  type        = string
}

variable "lock_table_name" {
  description = "DynamoDB table name used for Terraform state locking."
  type        = string
  default     = "hybrid-fleet-terraform-locks"
}
