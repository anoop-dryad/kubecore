provider "aws" {
  region = var.region
}

# Get the AWS account ID for unique bucket naming
data "aws_caller_identity" "current" {}

locals {
  bucket_name = "${var.bucket_name_prefix}-${data.aws_caller_identity.current.account_id}"
  common_tags = {
    Project     = "kubecore"
    Environment = "platform"
    ManagedBy   = "terraform-bootstrap"
    Description = "Bootstrap resources for kubecore Terraform state"
  }
}

# ─── S3 bucket for Terraform state ──────────────────────────────────────
resource "aws_s3_bucket" "tfstate" {
  bucket = local.bucket_name

  # Protect from accidental destroy
  lifecycle {
    prevent_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = local.bucket_name
  })
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─── DynamoDB table for state locking ────────────────────────────────────
resource "aws_dynamodb_table" "tfstate_lock" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = var.lock_table_name
  })
}
