# kubecore — Bootstrap

One-time bootstrap that creates Terraform state storage for kubecore.

This is a separate Terraform project. It uses **local state** intentionally —
the chicken-and-egg problem of "you can't store Terraform state in something
Terraform manages."

## What this creates

- **S3 bucket**: `kubecore-tfstate-<account-id>` (versioned, encrypted, private)
- **DynamoDB table**: `kubecore-tfstate-lock` (for state locking when multiple people apply)

Both resources have `prevent_destroy = true` — Terraform refuses to delete them
even if you try.

## Usage

\`\`\`bash
cd bootstrap

# First time

terraform init
terraform plan
terraform apply

# See outputs

terraform output
\`\`\`

## Important

- This directory's `terraform.tfstate` is **local** and gitignored
- Do NOT commit `terraform.tfstate` or any `.tfstate.backup` files
- Back up the state file to a private location periodically (it's tiny)
- If you lose the state file, you'll need to `terraform import` the existing resources

## After running

Use the output `backend_config` to populate `kubecore/envs/<env>/backend.tf`.

## Destroying

Don't, normally. If you really must:

1. Edit `main.tf` and remove the `lifecycle { prevent_destroy = true }` blocks
2. `terraform apply` (removes the protection)
3. `terraform destroy`

Then you've lost the bucket and any state stored in it — which would orphan
all the resources kubecore manages. Recovery requires `terraform import`.
