#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# kubecore — Bootstrap Terraform state storage
#
# Creates the S3 bucket that will hold Terraform state for kubecore.
#
# This is the "chicken-and-egg" bootstrap: Terraform needs state storage
# to run, and you can't store state in something Terraform manages. So we
# create the bucket once via AWS CLI, then all Terraform references it.
#
# Safe to run multiple times:
#   - Bucket already exists → skipped (with message)
#   - Configurations re-applied each run (idempotent)
#
# Prerequisites:
#   - AWS CLI installed and configured (`aws configure`)
#   - IAM user with permissions: s3:CreateBucket, s3:PutBucketVersioning,
#     s3:PutBucketEncryption, s3:PutBucketPublicAccessBlock
#
# Usage:
#   ./scripts/bootstrap.sh
#
# Optional overrides via env vars:
#   REGION=eu-west-1 ./scripts/bootstrap.sh
#   BUCKET_PREFIX=myproject-tfstate ./scripts/bootstrap.sh
# ─────────────────────────────────────────────────────────────────────────────

#set -e                     Exit immediately if any command fails
#set -u                     Exit if any unset variable is used (typos = error, not silent empty)
#set -o pipefail            A failure anywhere in a pipeline fails the whole pipeline
set -euo pipefail

# ─── Configuration ─────────────────────────────────────────────────────────
REGION="${REGION:-eu-central-1}"
BUCKET_PREFIX="${BUCKET_PREFIX:-kubecore-tfstate}"

# ─── Colors for nicer output ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}ℹ${NC}  $*"; }
success() { echo -e "${GREEN}✅${NC} $*"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $*"; }
error()   { echo -e "${RED}❌${NC} $*" >&2; }

# ─── Pre-flight checks ─────────────────────────────────────────────────────
echo "──────────────────────────────────────────────────────────"
echo "  kubecore — Bootstrap Terraform state storage"
echo "──────────────────────────────────────────────────────────"
echo

info "Running pre-flight checks..."

# Check AWS CLI is installed
if ! command -v aws &> /dev/null; then
  error "aws CLI not found. Install: brew install awscli"
  exit 1
fi

# Check AWS credentials work
if ! aws sts get-caller-identity &> /dev/null; then
  error "AWS credentials not configured or invalid."
  error "Run: aws configure"
  exit 1
fi

# Get account info
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
BUCKET="${BUCKET_PREFIX}-${ACCOUNT_ID}"

# Refuse to run as root account (best practice)
if [[ "$USER_ARN" == *":root" ]]; then
  error "You're running as the AWS root account. This is dangerous."
  error "Create an IAM user with AdministratorAccess and run 'aws configure' with its keys."
  exit 1
fi

success "AWS credentials valid"
echo "    Account ID: ${ACCOUNT_ID}"
echo "    IAM user:   ${USER_ARN}"
echo "    Region:     ${REGION}"
echo "    Bucket:     ${BUCKET}"
echo

# Confirm before continuing
read -rp "Proceed with bootstrap? [y/N] " CONFIRM
if [[ "${CONFIRM,,}" != "y" ]]; then
  warn "Aborted by user."
  exit 0
fi
echo

# ─── 1. Create the S3 bucket ──────────────────────────────────────────────
info "Step 1/4: Creating S3 bucket..."

if aws s3api head-bucket --bucket "${BUCKET}" --region "${REGION}" 2>/dev/null; then
  warn "Bucket '${BUCKET}' already exists. Skipping creation."
else
  if [[ "${REGION}" == "us-east-1" ]]; then
    # us-east-1 is the default and doesn't accept LocationConstraint
    aws s3api create-bucket \
      --bucket "${BUCKET}" \
      --region "${REGION}"
  else
    # All other regions REQUIRE LocationConstraint (AWS quirk)
    aws s3api create-bucket \
      --bucket "${BUCKET}" \
      --region "${REGION}" \
      --create-bucket-configuration "LocationConstraint=${REGION}"
  fi
  success "Bucket created: ${BUCKET}"
fi

# ─── 2. Enable versioning ──────────────────────────────────────────────────
# Versioning lets us recover from accidental state corruption or deletion.
# Past versions of terraform.tfstate are preserved.
info "Step 2/4: Enabling versioning..."

aws s3api put-bucket-versioning \
  --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled

success "Versioning enabled"

# ─── 3. Enable encryption at rest ─────────────────────────────────────────
# SSE-S3 (AES256) is free and managed entirely by AWS. For more control
# you could use SSE-KMS with a customer-managed key, but that costs more.
info "Step 3/4: Enabling encryption..."

aws s3api put-bucket-encryption \
  --bucket "${BUCKET}" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

success "Encryption enabled (SSE-S3 / AES256)"

# ─── 4. Block public access ───────────────────────────────────────────────
# State files contain resource IDs and sometimes sensitive data. They
# must never be publicly accessible. This is belt-and-suspenders on top
# of default IAM permissions.
info "Step 4/4: Blocking public access..."

aws s3api put-public-access-block \
  --bucket "${BUCKET}" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

success "Public access blocked"

# ─── Done ───────────────────────────────────────────────────────────────────
echo
echo "──────────────────────────────────────────────────────────"
success "Bootstrap complete"
echo "──────────────────────────────────────────────────────────"
echo
echo "Next steps:"
echo
echo "  1. Update terraform/backend.tf with the bucket name:"
echo
echo "     terraform {"
echo "       backend \"s3\" {"
echo "         bucket               = \"${BUCKET}\""
echo "         key                  = \"kubecore.tfstate\""
echo "         region               = \"${REGION}\""
echo "         encrypt              = true"
echo "         use_lockfile         = true"
echo "         workspace_key_prefix = \"workspaces\""
echo "       }"
echo "     }"
echo
echo "  2. Initialize Terraform:"
echo
echo "     cd terraform"
echo "     terraform init"
echo
echo "  3. Create the dev workspace:"
echo
echo "     terraform workspace new dev"
echo
echo "  4. Verify with a plan:"
echo
echo "     terraform plan"
echo