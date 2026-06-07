output "state_bucket_name" {
  description = "S3 bucket name for Terraform state — reference in backend.tf"
  value       = aws_s3_bucket.tfstate.id
}

output "state_lock_table_name" {
  description = "DynamoDB table name for state locking — reference in backend.tf"
  value       = aws_dynamodb_table.tfstate_lock.id
}

output "region" {
  description = "AWS region of state storage"
  value       = var.region
}

output "backend_config" {
  description = "Backend configuration to copy into kubecore/envs/*/backend.tf"
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.tfstate.id}"
        key            = "envs/<env-name>/terraform.tfstate"
        region         = "${var.region}"
        dynamodb_table = "${aws_dynamodb_table.tfstate_lock.id}"
        encrypt        = true
      }
    }
  EOT
}
