# kubecore

> Platform infrastructure for running Kubernetes workloads on AWS. Terraform-managed EKS cluster, VPC, IAM, and cluster add-ons. Consumed by application repos (e.g. `k8s-springboot-platform`).

This is a project to mirror real-world platform-engineering patterns. The structure follows what you'd see at a production-grade company — separate platform repo, multi-environment via Terraform workspaces, modular Terraform.

---

## What This Repo Contains

```
kubecore/
├── terraform/                  # All Terraform code
│   ├── versions.tf             # Required Terraform + provider versions
│   ├── backend.tf              # S3 remote state config
│   ├── providers.tf            # AWS provider config + default tags
│   ├── variables.tf            # Input variables
│   ├── main.tf                 # Module composition
│   ├── outputs.tf              # Exported values (consumed by app repos)
│   ├── vpc/                    # VPC module
│   ├── eks/                    # EKS cluster module
│   └── eks-addons/             # Cluster add-ons (ALB controller, etc.)
│
├── scripts/                    # Helper scripts
├── k8s/                        # Optional: shared K8s manifests
├── .github/                    # CI/CD workflows (future)
├── .gitignore
└── README.md                   # this file
```

---

## Prerequisites

Before you can use this repo, you need:

### One-Time AWS Setup

1. **AWS account** with billing alerts configured (see "Billing Discipline" below)
2. **IAM user** with `AdministratorAccess` policy (do NOT use the root account):
   ```bash
   # Verify your IAM user identity
   aws sts get-caller-identity
   # ARN should end with user/<your-iam-user>, not user/root
   ```
3. **AWS CLI** configured for the region:
   ```bash
   aws configure
   # Region: eu-central-1
   # Output format: json
   ```

### Tooling

Required versions:

| Tool      | Minimum version | Install                       |
| --------- | --------------- | ----------------------------- |
| Terraform | 1.10+           | `brew install terraform`      |
| AWS CLI   | 2.x             | `brew install awscli`         |
| kubectl   | 1.28+           | `brew install kubernetes-cli` |
| Helm      | 3.12+           | `brew install helm`           |

Verify each:

```bash
terraform version
aws --version
kubectl version --client
helm version
```

---

## Bootstrap (One-Time Setup)

Before any Terraform in this repo can run, an S3 bucket must exist to hold Terraform's state. This is the chicken-and-egg problem: Terraform needs state storage to run, and you can't store state in something Terraform manages.

A bootstrap script handles this automatically:

\`\`\`bash
./scripts/bootstrap.sh
\`\`\`

The script:

- Verifies AWS CLI is configured and credentials work
- Refuses to run as the root account
- Creates the state bucket (`kubecore-tfstate-<account-id>`) in eu-central-1
- Enables versioning, encryption, and blocks public access
- Is idempotent — safe to re-run; existing bucket is skipped, settings are re-applied
- Prints the `backend.tf` config to paste into Terraform

State locking uses S3 native lock files (`use_lockfile = true`) — no separate DynamoDB table needed. This requires Terraform 1.10+.

### Customizing

The script accepts environment variables for non-default setups:

\`\`\`bash
REGION=eu-west-1 ./scripts/bootstrap.sh
BUCKET_PREFIX=mycompany-tfstate ./scripts/bootstrap.sh
\`\`\`

See `scripts/bootstrap.sh` for full details.

**Save the bucket name.** You'll edit `terraform/backend.tf` to reference it.

State locking uses S3 native lock files (`use_lockfile = true`) — no separate DynamoDB table needed. This requires Terraform 1.10+.

---

## First-Time Setup of This Repo

After the bootstrap is done:

1. **Edit `terraform/backend.tf`** — replace `<ACCOUNT_ID>` with your AWS account ID:

   ```hcl
   bucket = "kubecore-tfstate-123456789012"
   ```

2. **Initialize Terraform:**

   ```bash
   cd terraform
   terraform init
   ```

   This downloads the AWS provider and configures the S3 backend.

3. **Create the `dev` workspace:**

   ```bash
   terraform workspace new dev
   terraform workspace list
   # * dev
   #   default
   ```

   The asterisk shows which workspace you're currently using.

4. **Verify the setup:**
   ```bash
   terraform plan
   ```
   Should report "No changes" since no resources are defined yet.

---

## Working With kubecore

### Daily Workflow

```bash
cd terraform

# Make sure you're in the right workspace
terraform workspace show
# Should print: dev

# See what would change
terraform plan

# Apply changes
terraform apply
```

### Adding Resources

Resources are organized into modules under `terraform/`. To add a new resource:

1. **Add to an existing module** if it fits (e.g. another subnet → `vpc/`)
2. **Create a new module** if it's a new concern (e.g. `terraform/route53/`)
3. **Compose the module** in `terraform/main.tf`
4. **Plan and apply**

### Switching Environments

This repo uses **Terraform workspaces** for environments. To add more:

```bash
# Create a new workspace
terraform workspace new staging

# Switch between
terraform workspace select dev
terraform workspace select staging
```

Each workspace has its own state file in S3. Resources in one workspace don't affect another. Resource names automatically include the workspace name via the `local.workspace` expression.

State paths in S3:

```
s3://kubecore-tfstate-<account>/
├── kubecore.tfstate                      ← default workspace (unused)
└── workspaces/
    ├── dev/kubecore.tfstate              ← dev workspace state
    ├── staging/kubecore.tfstate          ← staging workspace state
    └── prod/kubecore.tfstate              ← prod workspace state
```

For now, only `dev` is built. Same code supports additional workspaces when needed.

---

## Cost Management

EKS is **not** free. The control plane alone is ~$73/month, regardless of how much you use it. Add nodes, load balancers, NAT gateways, and you're looking at $130-180/month for a 24/7 setup.

### Tear Down When Not in Use

To save money, destroy everything at end of day:

```bash
cd terraform
terraform destroy
# Type 'yes' to confirm
```

Recreate the next day:

```bash
terraform apply
# Type 'yes' to confirm
```

A full tear-down + bring-up cycle takes ~25 minutes total (15 to apply, 10 to destroy). With nightly tear-down, monthly cost drops to ~$30-60.

### Monitoring Spend

Billing alerts are critical. See "Billing Discipline" below.

### What Gets Destroyed (and What Doesn't)

`terraform destroy` removes everything managed by Terraform in the current workspace:

- VPC, subnets, NAT gateways
- EKS cluster
- Node groups
- IAM roles
- Cluster add-ons

What it does NOT remove:

- The S3 state bucket (intentional — bootstrap doesn't touch this)
- Your IAM user (created manually)
- AWS account itself
- Any resources you created manually in the AWS Console

---

## Billing Discipline

### Set Up Budget Alerts (Required)

AWS Console → Billing → Budgets → Create budget:

- **Budget type**: Cost budget
- **Amount**: $100 (or your comfort level)
- **Period**: Monthly, recurring (no end date)
- **Alerts** at 50%, 80%, 100%, 120% of budget
- **Email**: your real email

This is non-negotiable. The 120% alert is your "something is badly wrong" safety net.

### Daily Sanity Check

Before any `terraform apply` session:

```bash
# Confirm correct account
aws sts get-caller-identity

# Confirm correct region
aws configure get region

# Quick cost-so-far check (Cost Explorer or Billing dashboard)
```

30-second habit. Catches mistakes before they cost you.

### Forgotten Resources

The expensive AWS resources to watch for:

| Resource              | Cost if left running |
| --------------------- | -------------------- |
| EKS control plane     | $73/month            |
| NAT Gateway           | $32/month + data     |
| RDS instance          | $15-50/month         |
| EBS volumes           | $0.10/GB/month       |
| Public IPv4 (new!)    | $3.65/month each     |
| Elastic Load Balancer | $22/month            |

If you've torn down via `terraform destroy` but the cost alert still fires, check:

- AWS Console → EC2 → Volumes (orphaned EBS)
- AWS Console → EC2 → Network Interfaces (orphaned ENIs from failed deletes)
- AWS Console → VPC → NAT Gateways (sometimes survive)

---

## State Management

### Where State Lives

- **Local development**: still uses S3 backend (configured in `backend.tf`)
- **State file path** (default workspace): `s3://kubecore-tfstate-<account>/kubecore.tfstate`
- **State file path** (dev workspace): `s3://kubecore-tfstate-<account>/workspaces/dev/kubecore.tfstate`
- **Locking**: Native S3 locks via `use_lockfile = true` (`.tflock` files)

### What's In the State File

Terraform's state file tracks all resources it manages — their IDs, attributes, and dependencies. **Do not edit it manually.** Use `terraform import`, `terraform state rm`, `terraform state mv` for state surgery.

### Backup Discipline

S3 versioning is enabled on the state bucket. Past versions of state are preserved. To recover:

```bash
# List state file versions
aws s3api list-object-versions \
  --bucket kubecore-tfstate-<account> \
  --prefix workspaces/dev/kubecore.tfstate

# Restore a specific version
aws s3api copy-object \
  --bucket kubecore-tfstate-<account> \
  --copy-source "kubecore-tfstate-<account>/workspaces/dev/kubecore.tfstate?versionId=<version>" \
  --key workspaces/dev/kubecore.tfstate
```

---

## How Application Repos Consume This

The kubecore repo creates platform-level infrastructure. App repos (e.g. `k8s-springboot-platform`) deploy workloads onto it.

Apps reference kubecore's outputs in one of two ways:

### Option A: Terraform Remote State (tight coupling)

```hcl
# In your app repo's Terraform
data "terraform_remote_state" "kubecore" {
  backend = "s3"
  config = {
    bucket = "kubecore-tfstate-<account>"
    key    = "workspaces/dev/kubecore.tfstate"
    region = "eu-central-1"
  }
  workspace = "dev"
}

# Reference outputs
locals {
  cluster_name = data.terraform_remote_state.kubecore.outputs.cluster_name
  vpc_id       = data.terraform_remote_state.kubecore.outputs.vpc_id
}
```

### Option B: AWS Data Sources (loose coupling, preferred)

```hcl
# Look up by known name/tag
data "aws_eks_cluster" "main" {
  name = "kubecore-dev"
}

data "aws_vpc" "main" {
  tags = {
    Project   = "kubecore"
    Workspace = "dev"
  }
}
```

Option B is preferred — no dependency on kubecore's state structure. Just AWS resources discovered by tags.

---

## What kubecore Does NOT Do

By design, kubecore does NOT manage:

- **Application workloads** — those are in app repos (e.g. `k8s-springboot-platform/k8s/`)
- **Application databases (RDS)** — app-specific, lives in app repos
- **Application secrets** — app repos use External Secrets pointing at AWS Secrets Manager
- **Application-specific IAM** — IRSA roles for app pods live in app repos

This separation keeps platform changes from being entangled with app changes.

---

## Directory Conventions

### `terraform/` Subdirectories

Each subdirectory is a Terraform module. Naming convention:

- Lowercase, hyphens not underscores (e.g. `eks-addons`, not `eks_addons`)
- Singular nouns (e.g. `vpc`, not `vpcs`)
- One concern per module

### File Naming Within a Module

Each module follows the same file structure:

```
modules/<name>/
├── main.tf          # primary resources
├── variables.tf     # inputs
├── outputs.tf       # exported values
├── versions.tf      # optional: provider version constraints for the module
└── README.md        # what this module does, inputs/outputs documented
```

---

## Troubleshooting

### `terraform init` fails with "bucket does not exist"

The bootstrap step wasn't run, or the bucket name in `backend.tf` doesn't match the actual bucket. Verify:

```bash
aws s3 ls | grep kubecore-tfstate
```

Update the bucket name in `terraform/backend.tf` to match.

### `terraform apply` fails with "Error acquiring the state lock"

Another `terraform apply` is running, or a previous one crashed without releasing the lock. To force-unlock:

```bash
# Find the lock ID from the error message, then:
terraform force-unlock <LOCK_ID>
```

Only do this if you're certain no other apply is running.

### Resources are in AWS but not in Terraform state

Someone (maybe past-you) created resources manually. Import them:

```bash
terraform import <resource_address> <aws_id>
# Example:
terraform import aws_vpc.main vpc-0a1b2c3d
```

### `aws sts get-caller-identity` returns root account

You're using the root account. Stop. Create an IAM user with `AdministratorAccess`, generate access keys, and reconfigure:

```bash
aws configure
```

### Cost spike alert

1. Open AWS Cost Explorer
2. Filter by tag: `Project = kubecore`
3. Look for unexpected resources
4. If from a failed `terraform destroy`, run destroy again and check manually:
   ```bash
   aws ec2 describe-volumes --filters "Name=status,Values=available" --region eu-central-1
   aws ec2 describe-network-interfaces --filters "Name=status,Values=available" --region eu-central-1
   ```

---

## Related Repositories

- **k8s-springboot-platform** — example app repo that consumes kubecore outputs

---

## References

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform S3 Backend](https://developer.hashicorp.com/terraform/language/backend/s3)
- [Terraform Workspaces](https://developer.hashicorp.com/terraform/cli/workspaces)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)

---

_Last updated: 2026-06-08_
