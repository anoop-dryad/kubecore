variable "region" {
  description = "AWS region for Terraform state storage"
  type        = string
  default     = "eu-central-1"
}

variable "bucket_name_prefix" {
  description = "Prefix for the state bucket name (account ID will be appended)"
  type        = string
  default     = "kubecore-tfstate"
}

variable "lock_table_name" {
  description = "DynamoDB table name for Terraform state locking"
  type        = string
  default     = "kubecore-tfstate-lock"
}
