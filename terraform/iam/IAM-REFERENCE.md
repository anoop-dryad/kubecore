# IAM — Complete Reference

> Personal reference for understanding AWS IAM: identities, policies, roles, and how to decide what to create when adding new AWS resources. Read top-to-bottom on first encounter; use as a lookup later.

---

## Table of Contents

1. [The Core Mental Model — Three Questions](#the-core-mental-model)
2. [Identities — Who Can Act](#identities)
3. [Policies — What They're Allowed to Do](#policies)
4. [Roles in Depth](#roles-in-depth)
5. [Trust Policy vs Permission Policy](#trust-policy-vs-permission-policy)
6. [Managed Policies vs Inline Policies](#managed-vs-inline-policies)
7. [Resource Policies vs IAM Policies](#resource-policies-vs-iam-policies)
8. [How AWS Decides Allow / Deny](#how-aws-decides)
9. [IRSA — IAM Roles for Service Accounts](#irsa)
10. [Service-Linked Roles](#service-linked-roles)
11. [The kubecore IAM Module](#the-kubecore-iam-module)
12. [Adding a New Resource — Decision Flow](#decision-flow)
13. [Common Patterns](#common-patterns)
14. [Anti-Patterns to Avoid](#anti-patterns)
15. [Troubleshooting](#troubleshooting)
16. [Glossary](#glossary)

---

## The Core Mental Model

Every IAM rule answers three questions:

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│      WHO?        │     │     WHAT?        │     │     TO WHAT?     │
│   (Principal)    │ ──→ │    (Actions)     │ ──→ │   (Resources)    │
└──────────────────┘     └──────────────────┘     └──────────────────┘

  WHO can do something?
  WHAT can they do?
  TO WHAT can they do it?
```

That's the entire IAM mental model. Everything else is just how AWS implements those three concepts.

### Quick Example

"The EKS cluster can read/write to ENIs in the VPC."

```
WHO     = the EKS service (via a role)
WHAT    = ec2:CreateNetworkInterface, ec2:DescribeNetworkInterfaces, etc.
TO WHAT = the ENIs in this account
```

This single statement, written in IAM JSON, looks like:

```json
{
  "Effect": "Allow",
  "Action": [
    "ec2:CreateNetworkInterface",
    "ec2:DescribeNetworkInterfaces"
  ],
  "Resource": "*"
}
```

Plus a trust policy saying "EKS service can assume this role."

When you read any IAM policy, ask the three questions. You'll always find the answers.

---

## Identities

In AWS, an **identity** is anything that can make API calls. There are four kinds.

### 1. AWS Account Root User

The original god-mode account. Created when you sign up. **Don't use it.**

- Has unrestricted access to everything
- Can't be restricted (its permissions can't be removed)
- Can do dangerous things only it can do (close account, change billing)
- Use it once at the start to set up an IAM admin user, then never again

### 2. IAM User

A long-lived identity for a specific person or system.

```
- Has a username and (optionally) a password for Console
- Has (optionally) access keys for CLI/API
- Permissions attached directly to the user
- Best practice: enable MFA
```

**When to use**:
- Real humans doing work in AWS
- Long-running automation that can't use roles (rare)
- Initial IAM admin (before you set up SSO)

**When NOT to use**:
- AWS services (use roles instead)
- Applications running on EC2/EKS/Lambda (use roles instead)
- Anything where you'd want the credentials to rotate automatically

### 3. IAM Role

A temporary identity that can be assumed by trusted entities.

```
- No long-term credentials
- "Assumed" by something else, granting temporary credentials
- Permissions attached to the role, not the assumer
- The most flexible IAM construct
```

**When to use**:
- AWS services (e.g., "EKS can do X" means EKS assumes a role)
- EC2 instances (instance profile)
- Lambda functions
- Cross-account access
- Federated users (SSO, OIDC)
- EKS pods (via IRSA)

**Almost everything in production uses roles, not users.**

### 4. Federated Identity

Users from outside AWS who get temporary AWS credentials.

```
- Backed by an identity provider (Okta, Google, AD, etc.)
- User authenticates with the IdP
- IdP gives them temporary AWS credentials by assuming a role
```

Used for SSO and modern enterprise auth. Conceptually similar to roles for federated users.

### Decision: User or Role?

```
Is the "thing" that needs to access AWS:

  A human?
    └─ Use SSO (federated) if available
       Otherwise: IAM user with MFA

  An AWS service (EKS, Lambda, S3)?
    └─ Use a role

  An EC2 instance?
    └─ Use a role via instance profile

  A Kubernetes pod?
    └─ Use a role via IRSA

  An application in CI/CD?
    └─ Use OIDC federation (preferred)
       Otherwise: IAM user with rotated access keys

  Cross-account?
    └─ Use a role with cross-account trust
```

When in doubt: **role**.

---

## Policies

A **policy** is a JSON document that grants or denies permissions.

### Policy Anatomy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowEC2ReadOnly",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeVolumes"
      ],
      "Resource": "*"
    }
  ]
}
```

Element by element:

- **`Version`**: always `"2012-10-17"`. AWS just hasn't released a new version. Set it and forget it.
- **`Statement`**: an array. One policy can have many statements.
- **`Sid`** (optional): "Statement ID." Just a label for humans, doesn't affect anything. Useful when debugging.
- **`Effect`**: `"Allow"` or `"Deny"`. Default is implicit deny — if no statement allows, the action is denied.
- **`Action`**: what AWS API calls are covered. Format: `<service>:<ApiName>`.
- **`Resource`**: which AWS resources the actions apply to. ARN format or `*` for all.

### Optional Elements

```json
{
  "Sid": "AllowS3ReadFromOneBucket",
  "Effect": "Allow",
  "Action": "s3:GetObject",
  "Resource": "arn:aws:s3:::my-bucket/*",
  "Condition": {
    "StringEquals": {
      "aws:RequestedRegion": "eu-central-1"
    }
  }
}
```

- **`Condition`**: additional constraints. "Only allow if the request comes from this region / IP / has this tag / etc."
- **`Principal`** (only in resource policies, not IAM policies): who the policy applies to.
- **`NotAction` / `NotResource`** (rarely used): inverse matching. Avoid — confusing and error-prone.

### Wildcards

```
Action:
  "s3:GetObject"           → just that one action
  "s3:Get*"                → all S3 actions starting with Get (GetObject, GetBucketLocation, etc.)
  "s3:*"                   → all S3 actions
  "*"                      → all actions in all services (godmode — usually wrong)

Resource:
  "arn:aws:s3:::my-bucket"             → just the bucket itself (not its objects)
  "arn:aws:s3:::my-bucket/*"           → all objects in the bucket
  "arn:aws:s3:::my-bucket/prefix/*"    → objects under a specific prefix
  "*"                                  → all resources of all types
```

### ARN Format

```
arn:aws:<service>:<region>:<account-id>:<resource-type>/<resource-name>
```

Examples:

```
arn:aws:s3:::my-bucket                                      ← S3 has no region/account in bucket ARNs
arn:aws:iam::123456789012:role/my-role                      ← IAM has no region (global service)
arn:aws:ec2:eu-central-1:123456789012:instance/i-abc123     ← typical format
arn:aws:rds:eu-central-1:123456789012:db:my-database        ← RDS uses colon separator
arn:aws:eks:eu-central-1:123456789012:cluster/kubecore-dev  ← EKS clusters
```

ARNs are how IAM refers to specific resources. When writing policies, you'll spend time looking up the exact ARN format for each service. AWS docs cover this per-service.

### Reading a Policy

Whenever you see a policy, ask the three questions:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:GetObject", "s3:PutObject"],
    "Resource": "arn:aws:s3:::my-app-data/*"
  }]
}
```

- **WHO**: whoever this policy is attached to (we'd have to check)
- **WHAT**: download and upload S3 objects
- **TO WHAT**: any object inside the `my-app-data` bucket

Three questions, one policy. Every time.

---

## Roles in Depth

Roles are the most-used IAM construct. They deserve a dedicated section.

### What Makes a Role Different from a User

A user has:
- Long-term credentials (password, access keys)
- Permissions attached to it
- Identity directly usable

A role has:
- **No credentials**
- Permissions attached to it
- **A trust policy** saying who can "assume" it
- When something assumes the role, AWS issues **temporary credentials** valid for a short time (1-12 hours)

Think of a role as a "costume" that anyone trusted can wear temporarily. While wearing it, they have its permissions. When they take it off (token expires), they're back to their original identity.

### Why Roles Are Better Than Users for Most Things

Long-term credentials are dangerous:

- Access keys get leaked (committed to GitHub, captured in logs)
- Once leaked, attacker has indefinite access until you rotate
- Rotating keys is operational toil
- Hard to track who has what

Temporary credentials from roles solve all of this:

- Credentials expire automatically (default 1 hour)
- No long-term secret to leak
- AssumeRole calls are logged in CloudTrail — full audit trail
- Rotation is automatic

For these reasons, AWS recommends roles for almost everything that's not a human.

### Anatomy of a Role

A role has two distinct policies (this is where confusion starts):

```
┌─────────────────────────────────────────────────────┐
│                  IAM Role                           │
│                                                     │
│  ┌─────────────────────┐  ┌─────────────────────┐  │
│  │  Trust Policy       │  │  Permission Policy  │  │
│  │                     │  │                     │  │
│  │  WHO can assume     │  │  WHAT can they do   │  │
│  │  this role?         │  │  once they assume?  │  │
│  │                     │  │                     │  │
│  │  (Principal)        │  │  (Actions+Resources)│  │
│  └─────────────────────┘  └─────────────────────┘  │
│                                                     │
└─────────────────────────────────────────────────────┘
```

Both are policies. Both are JSON. They answer different questions:

- **Trust policy**: WHO is allowed to assume the role
- **Permission policy**: WHAT the role can do (after being assumed)

This is the source of much confusion. Read the next section carefully.

### Role Assumption Flow

When EKS uses a role, here's what happens:

```
[1] EKS service (eks.amazonaws.com) wants to do something on your behalf

[2] EKS calls: sts:AssumeRole on arn:aws:iam::123:role/eks-cluster-role

[3] AWS STS checks the role's TRUST POLICY
    Question: "Does the trust policy say eks.amazonaws.com is allowed?"
    
    Trust policy:
      Principal: { Service: "eks.amazonaws.com" }
      Action: "sts:AssumeRole"
      Effect: Allow
    
    Answer: Yes → continue
            No  → AccessDenied, stop

[4] STS issues temporary credentials valid for ~1 hour
    These credentials have the role's PERMISSION POLICY

[5] EKS uses those credentials to call ec2:CreateNetworkInterface, etc.

[6] AWS checks PERMISSION POLICY
    Question: "Can this role do ec2:CreateNetworkInterface?"
    
    Permission policy (AmazonEKSClusterPolicy):
      Effect: Allow
      Action: ec2:CreateNetworkInterface
      Resource: *
    
    Answer: Yes → action succeeds
            No  → AccessDenied
```

Two checks, two policies, one role. Both must allow for anything to happen.

---

## Trust Policy vs Permission Policy

This is the most-confused topic in IAM. Let me hammer it home.

### Two Different Questions, Two Different Policies

**Trust policy** answers: "Who is allowed to assume this role?"
**Permission policy** answers: "What can the role do once assumed?"

They live on the same role but they're checked at different times for different reasons.

### Trust Policy Example

For the EKS cluster role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "eks.amazonaws.com"
      }
    }
  ]
}
```

Read this as: "The EKS service (`eks.amazonaws.com`) is allowed to assume this role."

Key things:

- **`Action`** is always `sts:AssumeRole` (you're saying what action the principal can take, and the action of assuming a role is `sts:AssumeRole`)
- **`Principal`** is the thing being trusted — an AWS service, an account, a user, or a federated identity
- **`Resource`** is implicit — it's "this role" because the trust policy is attached to a specific role

### Permission Policy Example

Also attached to the same EKS cluster role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:CreateNetworkInterface",
        "ec2:DeleteNetworkInterface",
        "iam:PassRole"
      ],
      "Resource": "*"
    }
  ]
}
```

Read this as: "Whoever assumes this role can do these EC2 and IAM actions on any resource."

This is the **AmazonEKSClusterPolicy** managed policy (simplified). AWS publishes this so you don't have to write it.

### Putting It Together

```
                     ┌──────────────────────────────┐
                     │   IAM Role:                  │
                     │   eks-cluster-role           │
                     ├──────────────────────────────┤
                     │                              │
EKS service          │  Trust Policy:               │
   ↓                 │    Allow eks.amazonaws.com   │
"Let me assume" ───→ │    to sts:AssumeRole         │
                     │                              │
   ↓                 │  Permission Policy:          │
"Now do this" ─────→ │    Allow ec2:CreateENI       │
                     │    Allow ec2:DescribeENI     │
                     │    (etc.)                    │
                     │                              │
                     └──────────────────────────────┘

Both checks must pass for the action to succeed.
```

### What Confuses People

**Mistake 1**: putting `sts:AssumeRole` in a permission policy.
- That's already what the trust policy does.
- Putting it in the permission policy means "this role can assume other roles" (a different thing — used for role chaining)

**Mistake 2**: putting actions like `ec2:CreateENI` in a trust policy.
- Trust policies only have `sts:AssumeRole` (and related variants like `sts:TagSession`).
- Other actions don't make sense in a trust policy.

**Mistake 3**: thinking the role itself "does" things.
- Roles can't do anything on their own.
- Something must assume them first (get temporary credentials), then that something does things using those credentials.

### A Useful Analogy

Think of a role as a hotel room key card.

- **Trust policy** = front desk's rules about who they'll issue the card to ("guests of room 305")
- **Permission policy** = what the card actually unlocks ("room 305, gym, pool")

Front desk and the card unlock mechanism check different things at different times. Both need to agree for you to use the gym.

---

## Managed vs Inline Policies

Permission policies come in two flavors based on how they're stored.

### Managed Policies

Standalone policies that can be attached to multiple roles/users:

```
AWS-managed policies     (created by AWS, like AmazonS3ReadOnlyAccess)
Customer-managed policies (created by you, reusable across resources)
```

Pros:
- Reusable (one policy, multiple attachments)
- Versioned (you can roll back changes)
- Centralized — see all attachments in one place
- Visible in the IAM Console as standalone entities

When to use:
- You'll attach the same permissions to multiple roles/users
- AWS publishes one that fits your needs

### Inline Policies

Embedded directly in a role/user. Not reusable.

```
Role: eks-cluster-role
├── Trust policy
└── Inline permission policy (lives only inside this role)
```

Pros:
- Tightly coupled to one role — clear what permissions a role has
- No risk of accidentally detaching from multiple things
- Deleted when the role is deleted

When to use:
- Permissions specific to ONE role only
- Tight 1:1 coupling between role and policy

### AWS-Managed Policies — When to Use

AWS publishes hundreds of policies for common scenarios:

```
AdministratorAccess              → everything (avoid except for IAM admin user)
AmazonS3ReadOnlyAccess           → S3 read
AmazonEC2ContainerRegistryReadOnly → ECR pull
AmazonEKSClusterPolicy           → EKS control plane
AmazonEKSWorkerNodePolicy        → EKS worker nodes
AmazonEKS_CNI_Policy             → VPC CNI plugin
AmazonSSMManagedInstanceCore     → SSM Session Manager access
```

**Use AWS-managed policies whenever they fit.** Reasons:

- AWS maintains them — when EKS adds a new feature, the policy updates
- Less code to maintain
- Less chance of subtle permission bugs
- Documented and understood by anyone reading

If you're attaching them to your IAM resources today, you saw this in the kubecore IAM module.

### Customer-Managed Policies — When to Use

When AWS doesn't have a managed policy that fits, OR when you need to combine multiple sets of permissions.

```hcl
resource "aws_iam_policy" "auth_service_secrets_read" {
  name = "auth-service-secrets-read"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = "arn:aws:secretsmanager:eu-central-1:*:secret:auth-service/*"
    }]
  })
}

# Attach to a role
resource "aws_iam_role_policy_attachment" "auth_service" {
  role       = aws_iam_role.auth_service.name
  policy_arn = aws_iam_policy.auth_service_secrets_read.arn
}
```

Pattern: write the policy as a separate resource, attach to roles as needed.

### Inline — When to Use

For permissions truly specific to one role only:

```hcl
resource "aws_iam_role_policy" "inline_example" {
  name = "specific-to-this-role"
  role = aws_iam_role.my_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["dynamodb:GetItem"]
      Resource = "arn:aws:dynamodb:*:*:table/very-specific-table"
    }]
  })
}
```

Use inline sparingly. Most real-world cases benefit from managed (reusable, visible) policies.

### Decision

```
Permissions you need:

  AWS-managed policy exists?
    └─ Use it (AmazonEKSClusterPolicy, etc.)

  Multiple roles need the same custom permissions?
    └─ Customer-managed policy

  One role only, very specific?
    └─ Inline policy
```

---

## Resource Policies vs IAM Policies

Two policy types with similar names but different purposes. Easy to confuse.

### IAM Policies (Identity-Based)

Attached to **identities** (users, roles, groups). Says "this identity can do X."

```
Role: auth-service-role
└── IAM policy: can read from `users` DynamoDB table
```

When the role's bearer makes a request, AWS checks the IAM policy.

### Resource Policies (Resource-Based)

Attached to **resources** (S3 buckets, KMS keys, SNS topics, etc.). Says "these identities can do X to me."

```
S3 Bucket: my-uploads
└── Bucket policy: anyone in account 123 can read these objects
```

When anyone makes a request to that bucket, AWS checks the bucket policy too.

### Comparison

| Aspect | IAM Policy | Resource Policy |
|---|---|---|
| Attached to | Identity (user, role, group) | Resource (bucket, key, etc.) |
| Has Principal? | No (principal is the attached identity) | **Yes** (specifies who) |
| Use case | "What can THIS USER/ROLE do?" | "Who can access THIS BUCKET?" |
| Where in Console | IAM section | The resource's own settings |
| Common services | All identities | S3, KMS, SNS, SQS, Lambda, etc. |

### When to Use Each

**Use IAM policy when**:
- You're saying "this role can do X to many resources"
- The permissions are about the requester's job/function

**Use resource policy when**:
- You're saying "this resource can be accessed by Y people"
- The access is about the resource's protection
- You need cross-account access (resource policies can grant to other accounts directly)

### Both Together (Common)

For many use cases, you have BOTH:

```
Bucket "uploads":
  Resource policy: account 123 can do s3:GetObject

Role "auth-service":
  IAM policy: can do s3:GetObject on "uploads"
```

When a pod (assumed `auth-service` role) accesses the bucket:
- IAM check: does the role allow GetObject on uploads? ✓
- Resource check: does the bucket allow this account? ✓
- → Access granted

If either denies, access is denied. They both must allow.

### Resource Policy Example

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "AWS": "arn:aws:iam::123456789012:role/auth-service"
    },
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::uploads/*"
  }]
}
```

Note `Principal` is now present — this is the WHO. In IAM policies attached to identities, principal is implicit (the identity).

---

## How AWS Decides

When you make an API call, AWS runs a decision algorithm. Understanding it saves hours of debugging.

### The Decision Algorithm

```
[1] Default: implicit DENY (nothing is allowed unless something says so)

[2] Evaluate all applicable policies:
    - Identity policies (IAM policies on the user/role)
    - Resource policies (on the resource being accessed)
    - Permission boundaries (advanced feature)
    - Service control policies (organization-wide)
    - Session policies (if assuming role with restrictions)

[3] If ANY policy contains an explicit DENY → DENY (final answer)

[4] If NO policy contains ALLOW → DENY (implicit)

[5] If at least one ALLOW and no explicit DENY → ALLOW
```

### Key Rules

**Explicit deny always wins.** If any applicable policy says `"Effect": "Deny"` for an action, it's denied no matter how many allows exist.

**Implicit deny is the default.** If no policy explicitly allows, the action is denied. Don't think "I haven't denied it, so it should work" — you have to explicitly allow.

**Permissions are union'd, not intersected**, except for explicit denies. If you have two policies attached:

```
Policy A: Allow s3:GetObject on bucket-1
Policy B: Allow s3:PutObject on bucket-2
```

You can do GetObject on bucket-1 AND PutObject on bucket-2. Both are allowed. Multiple policies add up.

### Useful Diagram

```
                  Make API call
                      │
                      ▼
            ┌─────────────────────────┐
            │ Any explicit DENY in    │
            │ any applicable policy?  │
            └─────────────────────────┘
                      │
              ┌───────┴───────┐
             Yes              No
              │                │
              ▼                ▼
            DENY      ┌─────────────────────────┐
                      │ Any explicit ALLOW in   │
                      │ any applicable policy?  │
                      └─────────────────────────┘
                              │
                      ┌───────┴───────┐
                     Yes              No
                      │                │
                      ▼                ▼
                    ALLOW            DENY
                                  (implicit)
```

### Practical Implications

**You can't add permissions by saying "Allow * except X":**

```
Policy A: Allow s3:* on *
Policy B: Deny s3:DeleteObject on *
```

This works — explicit deny wins. But notice: you needed BOTH policies. The deny doesn't "narrow" the allow; both are evaluated.

**"Why is my role being denied?"** Common debugging:

1. Is there an explicit deny somewhere? (Most common cause)
2. Did I attach the policy correctly?
3. Does the policy actually have the action I need?
4. Is the resource ARN format right?
5. Are there conditions on the policy that aren't met?
6. Is there a resource policy denying me (S3, KMS)?
7. Is there an SCP at the org level?

The IAM Policy Simulator (in AWS Console) walks through this for you.

---

## IRSA

**IAM Roles for Service Accounts**. The way EKS pods get IAM permissions.

### The Problem IRSA Solves

Without IRSA, how does a pod get AWS credentials?

```
Option 1: AWS credentials baked into the container image
  ❌ Bad — credentials in image, leak if image is pulled
  ❌ Don't rotate

Option 2: Credentials in a Kubernetes Secret
  ❌ Still long-term credentials
  ❌ Need to rotate manually

Option 3: Use the node's IAM role
  ❌ All pods on the node share the same permissions
  ❌ Massive security violation (one pod gets compromised → all pods' permissions exposed)
```

IRSA solves this by giving each pod its own role, scoped to its specific service account.

### How IRSA Works

```
[1] You create an IAM role with a trust policy that trusts the EKS OIDC provider.

[2] You associate the role with a Kubernetes service account using an annotation:
    
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: auth-service-sa
      annotations:
        eks.amazonaws.com/role-arn: arn:aws:iam::123:role/auth-service-role

[3] You configure your pod to use that service account:
    
    spec:
      serviceAccountName: auth-service-sa
      containers:
        - name: app
          image: ...

[4] EKS injects a projected token volume into the pod containing a signed JWT
    issued by the EKS OIDC provider.

[5] AWS SDK in the pod reads the token, calls sts:AssumeRoleWithWebIdentity,
    presents the JWT to STS.

[6] STS validates the JWT signature against the OIDC provider (which AWS knows
    is trusted because of the role's trust policy).

[7] STS returns temporary AWS credentials.

[8] AWS SDK uses those credentials for all AWS API calls.

[9] Credentials auto-refresh every 1 hour. No manual rotation.
```

### Trust Policy for IRSA

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::123456789012:oidc-provider/oidc.eks.eu-central-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "oidc.eks.eu-central-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E:sub": "system:serviceaccount:auth-namespace:auth-service-sa",
        "oidc.eks.eu-central-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E:aud": "sts.amazonaws.com"
      }
    }
  }]
}
```

Key parts:

- **Principal**: the OIDC provider (set up when you create the EKS cluster)
- **Action**: `sts:AssumeRoleWithWebIdentity` (not regular `AssumeRole`)
- **Condition `sub`**: scopes to a specific namespace + service account
- **Condition `aud`**: ensures the JWT's audience is STS

The condition is critical — without it, ANY pod in ANY namespace could assume the role. With it, only the named service account can.

### IRSA Setup Pattern

For each pod that needs AWS access:

```
1. Create the IAM role with IRSA trust policy
2. Attach permission policies to the role (what the pod can do)
3. Create the Kubernetes service account with the role ARN annotation
4. Configure the pod's spec.serviceAccountName
5. The AWS SDK auto-handles the rest
```

When you eventually deploy auth-service to EKS, this is the pattern.

### IRSA vs Pod Identity (Newer Alternative)

AWS released **EKS Pod Identity** in late 2023 as a simpler alternative to IRSA. Similar concept, less setup. We won't use it in this project but mention it for awareness — when you see it in newer projects, it's IRSA's successor.

---

## Service-Linked Roles

A special type of role that AWS services create automatically.

### What They Are

When you start using certain AWS services, they automatically create an IAM role on your behalf:

```
First time you use EKS:    AWS creates AWSServiceRoleForAmazonEKS
First time you use ELB:    AWS creates AWSServiceRoleForElasticLoadBalancing
First time you use ECS:    AWS creates AWSServiceRoleForECS
```

### Properties

- **Auto-created** when the service is first used
- **Service-managed permissions** — you can't edit them
- **Service-owned** — you can't delete easily (have to delete via the service first)
- **Visible in IAM Console** with names starting with `AWSServiceRoleFor...`

### Why They Exist

Some services need permissions you can't easily replicate. AWS pre-defines these as service-linked roles. You don't have to know what permissions are needed; the service has its own role.

### Should You Worry About Them?

Mostly no. They appear automatically. You shouldn't try to delete or modify them. If you see one in the IAM Console, leave it alone.

The one thing to know: if you're getting "service-linked role doesn't exist" errors, you can manually create them:

```bash
aws iam create-service-linked-role --aws-service-name eks.amazonaws.com
```

Rare. Most services create them automatically on first use.

---

## The kubecore IAM Module

What the module creates and why.

### Module Contents

```
modules/iam/
├── main.tf       # The roles + policy attachments
├── variables.tf  # Inputs (environment, cluster_name)
└── outputs.tf    # Role ARNs (consumed by future EKS module)
```

### What It Creates

**EKS Cluster Role** (`{env}-{cluster}-eks-cluster-role`):

- **Trust policy**: `eks.amazonaws.com` can assume
- **Permission policy** (AWS-managed): `AmazonEKSClusterPolicy`
  - Permissions for the EKS control plane to manage VPC resources (ENIs, SGs, etc.) and load balancers

Used by: the EKS service to manage your cluster on your behalf.

**EKS Node Role** (`{env}-{cluster}-eks-node-role`):

- **Trust policy**: `ec2.amazonaws.com` can assume (because nodes are EC2 instances)
- **Permission policies** (all AWS-managed):
  - `AmazonEKSWorkerNodePolicy`: register with cluster, communicate with control plane
  - `AmazonEKS_CNI_Policy`: VPC CNI plugin for pod networking
  - `AmazonEC2ContainerRegistryReadOnly`: pull images from ECR

Used by: the EC2 instances running as Kubernetes worker nodes.

### Why These Specific Policies

AWS publishes managed policies for the exact permissions EKS needs. We use AWS-managed ones because:

1. **Maintained by AWS** — when EKS adds features, the policy updates
2. **Well-tested** — used by millions of EKS clusters
3. **Documented** — you can look up exactly what each grants
4. **Standard** — every EKS cluster uses the same ones

If you wrote them yourself, you'd inevitably miss a permission and spend hours debugging.

### What's NOT Created Yet

For future expansion:

```
✗ AWS Load Balancer Controller role     — needed when we install ALB Controller
✗ External Secrets Operator role        — needed when we install ESO
✗ Cluster Autoscaler role               — needed for autoscaling
✗ App-specific roles (auth-service, etc.) — created when apps deploy
✗ EBS CSI driver role                   — for persistent volumes
✗ VPC CNI driver role                   — for IPv6 or other advanced networking
```

These are all IRSA-style roles. We'll add them when needed.

### Outputs

The module exports two ARNs:

```hcl
output "eks_cluster_role_arn"  # for the future EKS cluster
output "eks_node_role_arn"     # for the future EKS node group
```

When we add the EKS module, it references these.

---

## Decision Flow

When adding a new AWS resource, ask these questions to decide IAM needs.

### Step 1: Does this resource need to call other AWS services?

**Yes** → continue to Step 2
**No** → no IAM role needed (rare — most resources call something)

### Step 2: What identity does it use?

```
AWS service (EKS, Lambda, RDS)?           → Service-Linked Role or service-trust role
EC2 instance?                              → Instance profile (wraps a role)
EKS pod?                                   → IRSA
CI/CD pipeline?                            → OIDC federation (preferred) or IAM user
Human user?                                → SSO (preferred) or IAM user
Cross-account?                             → Role with cross-account trust
```

### Step 3: What does it need to do?

Make a list of AWS actions. Be specific:

```
auth-service pod needs to:
  - Read secrets from Secrets Manager (specific secret only)
  - Write logs to CloudWatch (specific log group)
  - Maybe: connect to RDS (this is via IAM auth or via password? Decide.)
```

### Step 4: Is there a managed policy for this?

Check AWS docs for the service. Common ones:

```
S3 read/write       → AmazonS3FullAccess, AmazonS3ReadOnlyAccess (overly broad — usually too much)
ECR pull            → AmazonEC2ContainerRegistryReadOnly
CloudWatch Logs     → CloudWatchLogsFullAccess (broad, often fine)
RDS connect         → AmazonRDSReadOnlyAccess (only describes; for SQL access use IAM auth)
SSM Session Manager → AmazonSSMManagedInstanceCore
```

**If a managed policy is too broad**, write a custom policy. Don't grant access to everything when you need access to one specific resource.

### Step 5: Write the policy (if no managed policy fits)

```hcl
data "aws_iam_policy_document" "auth_service_permissions" {
  statement {
    effect = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      "arn:aws:secretsmanager:eu-central-1:*:secret:auth-service/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:eu-central-1:*:log-group:/aws/eks/kubecore-dev/auth-service:*"
    ]
  }
}

resource "aws_iam_policy" "auth_service" {
  name   = "auth-service-permissions"
  policy = data.aws_iam_policy_document.auth_service_permissions.json
}
```

### Step 6: Write the trust policy

```hcl
data "aws_iam_policy_document" "auth_service_assume_role" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    
    principals {
      type        = "Federated"
      identifiers = [var.eks_oidc_provider_arn]
    }
    
    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_issuer}:sub"
      values   = ["system:serviceaccount:default:auth-service-sa"]
    }
  }
}

resource "aws_iam_role" "auth_service" {
  name               = "auth-service-role"
  assume_role_policy = data.aws_iam_policy_document.auth_service_assume_role.json
}
```

### Step 7: Attach policies to role

```hcl
resource "aws_iam_role_policy_attachment" "auth_service" {
  role       = aws_iam_role.auth_service.name
  policy_arn = aws_iam_policy.auth_service.arn
}
```

### Step 8: Use the role

For pods, annotate the service account:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: auth-service-sa
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123:role/auth-service-role
```

For EC2 instances, create an instance profile:

```hcl
resource "aws_iam_instance_profile" "auth_service" {
  name = "auth-service-instance-profile"
  role = aws_iam_role.auth_service.name
}
```

### Decision Flow Diagram

```
┌──────────────────────────┐
│ New resource added       │
└──────────┬───────────────┘
           ↓
┌──────────────────────────┐
│ Calls other AWS services?│
└──────────┬───────────────┘
       Yes │
           ↓
┌──────────────────────────┐
│ Identity type?           │
└──────────┬───────────────┘
           │
    ┌──────┼──────┬──────┬───────┐
    │      │      │      │       │
   pod   EC2  service human  CI/CD
    │      │      │      │       │
   IRSA  inst. SLR/  SSO   OIDC
        profile srvc       fed
           │
           ↓
┌──────────────────────────┐
│ List required actions    │
└──────────┬───────────────┘
           ↓
┌──────────────────────────┐
│ AWS managed policy fits? │
└──────────┬───────────────┘
       Yes │  No
           │   ↓
           │ ┌──────────────────────┐
           │ │ Write custom policy  │
           │ └──────────┬───────────┘
           ↓            ↓
┌──────────────────────────┐
│ Write trust policy       │
└──────────┬───────────────┘
           ↓
┌──────────────────────────┐
│ Attach policy to role    │
└──────────┬───────────────┘
           ↓
┌──────────────────────────┐
│ Configure resource to    │
│ use the role             │
└──────────────────────────┘
```

---

## Common Patterns

### Pattern A: EKS Cluster Role

Used by EKS control plane. We have this in kubecore.

```hcl
data "aws_iam_policy_document" "eks_cluster_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume.json
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}
```

### Pattern B: EC2 Instance Role (Node Role)

Used by EKS workers. We have this in kubecore.

```hcl
data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
}

# Multiple managed policies
resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# EC2 instances reference roles via instance profile
resource "aws_iam_instance_profile" "node" {
  name = "eks-node-instance-profile"
  role = aws_iam_role.node.name
}
```

### Pattern C: IRSA Role for a Pod

Used by EKS pods. We'll build many of these.

```hcl
data "aws_iam_policy_document" "irsa_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    
    # Restrict to a specific service account
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_issuer_url}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account_name}"]
    }
    
    # Standard audience for EKS
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_issuer_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pod" {
  name               = "${var.app_name}-irsa-role"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume.json
}

# Attach app-specific permissions
resource "aws_iam_role_policy" "app" {
  name = "app-permissions"
  role = aws_iam_role.pod.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = "arn:aws:secretsmanager:*:*:secret:${var.app_name}/*"
    }]
  })
}
```

### Pattern D: Cross-Account Role

When you need to allow another account access:

```hcl
data "aws_iam_policy_document" "cross_account_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::OTHER_ACCOUNT_ID:root"]
    }
    
    # Optional: require an ExternalId to prevent confused deputy
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = ["a-shared-secret"]
    }
  }
}

resource "aws_iam_role" "cross_account" {
  name               = "shared-access-role"
  assume_role_policy = data.aws_iam_policy_document.cross_account_assume.json
}
```

### Pattern E: CI/CD via OIDC (GitHub Actions)

Modern pattern — no long-lived credentials in GitHub Secrets.

```hcl
data "aws_iam_policy_document" "github_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    
    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"]
    }
    
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    
    # Restrict to specific GitHub repo and branch
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:my-org/my-repo:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "github-actions-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_assume.json
}
```

This means GitHub Actions in your `main` branch can assume the role — no access keys to store.

---

## Anti-Patterns

Things to avoid.

### 1. Using `*` for Resources When You Could Be Specific

```hcl
# BAD
resource "aws_iam_role_policy" "bad" {
  policy = jsonencode({
    Statement = [{
      Action   = "s3:GetObject"
      Resource = "*"                    # ALL S3 objects in all buckets
    }]
  })
}

# GOOD
resource "aws_iam_role_policy" "good" {
  policy = jsonencode({
    Statement = [{
      Action   = "s3:GetObject"
      Resource = "arn:aws:s3:::my-app-data/*"   # Specific bucket
    }]
  })
}
```

The principle: **least privilege**. Grant only what's needed. If the role is compromised, the blast radius is smaller.

### 2. AdministratorAccess on Service Roles

```hcl
# BAD
resource "aws_iam_role_policy_attachment" "bad" {
  role       = aws_iam_role.auth_service.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"   # Nope
}
```

If auth-service is compromised, attacker has god mode. Always scope permissions to what the role actually needs.

### 3. Long-Lived Access Keys

```hcl
# BAD (mostly)
resource "aws_iam_access_key" "for_app" {
  user = aws_iam_user.app.name
}

# Then put the key in env vars / secrets manager
```

This creates long-lived credentials that can leak. Always prefer roles + temporary credentials.

Exception: legacy systems that can't use roles. Even then, rotate aggressively.

### 4. Trust Policy Without Conditions on IRSA

```hcl
# BAD — any pod in any namespace can assume
data "aws_iam_policy_document" "bad_irsa" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    # No condition! Any service account in the cluster can use this role.
  }
}

# GOOD — only specific SA can assume
data "aws_iam_policy_document" "good_irsa" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_issuer_url}:sub"
      values   = ["system:serviceaccount:auth:auth-service-sa"]
    }
  }
}
```

The condition is **required** for IRSA to be secure. Without it, the cluster's privilege boundary is broken.

### 5. Inline Policies for Reusable Permissions

If you find yourself copying the same inline policy across roles, extract it to a managed policy. Reusability beats embedded redundancy.

### 6. NotAction / NotResource

```hcl
# CONFUSING — avoid
{
  Effect    = "Allow"
  NotAction = "iam:*"          # "Allow everything EXCEPT IAM"
  Resource  = "*"
}
```

Inverse matching is hard to reason about. Use positive matching with explicit denies if needed.

### 7. Hardcoding ARNs in Policies

```hcl
# BAD
policy = jsonencode({
  Statement = [{
    Resource = "arn:aws:s3:::my-app-data-prod"   # Hardcoded
  }]
})

# GOOD
policy = jsonencode({
  Statement = [{
    Resource = aws_s3_bucket.app_data.arn        # References the actual bucket
  }]
})
```

Hardcoded ARNs break when you change names. Always reference the actual resource.

---

## Troubleshooting

### "AccessDenied" — Step-by-Step Debugging

**Step 1**: Read the full error.

```
An error occurred (AccessDenied) when calling the GetObject operation:
User: arn:aws:sts::123456789012:assumed-role/auth-service-role/abc
is not authorized to perform: s3:GetObject on resource:
arn:aws:s3:::my-bucket/file.txt
```

Three pieces of info to extract:
- **WHO**: `arn:aws:sts::123:assumed-role/auth-service-role/abc` — the assumed role session
- **WHAT**: `s3:GetObject`
- **TO WHAT**: `arn:aws:s3:::my-bucket/file.txt`

**Step 2**: Check the IAM policy attached to the role.

```bash
# List policies attached to the role
aws iam list-attached-role-policies --role-name auth-service-role
aws iam list-role-policies --role-name auth-service-role

# Get the actual policy content
aws iam get-policy-version --policy-arn ARN --version-id v1
```

Does any of them allow `s3:GetObject` on `arn:aws:s3:::my-bucket/*`?

**Step 3**: Check for explicit denies.

Look for `"Effect": "Deny"` in any attached policy. If found, that's your problem.

**Step 4**: Check resource policy.

```bash
aws s3api get-bucket-policy --bucket my-bucket
```

Does it deny based on conditions? IP restrictions? Account restrictions?

**Step 5**: Check service control policies (SCPs) if in an AWS Organization.

```bash
aws organizations list-policies-for-target --target-id <account-id> --filter SERVICE_CONTROL_POLICY
```

SCPs can block actions even if IAM allows them.

**Step 6**: Use the IAM Policy Simulator.

```
AWS Console → IAM → Policy Simulator
```

Select the role, the action, the resource. The simulator tells you which policies allowed/denied.

### "InvalidClientTokenId" or "SignatureDoesNotMatch"

Authentication issue, not authorization:

- Wrong access key
- Expired temporary credentials
- Clock skew between client and AWS (rare on modern systems)

```bash
# Verify credentials
aws sts get-caller-identity

# If using assumed role, check token expiration
aws sts get-session-token
```

### "Role is not authorized to perform AssumeRole on resource X"

Trust policy issue, not permission policy:

- The principal trying to assume isn't allowed in the trust policy
- For IRSA: the OIDC condition's `sub` doesn't match the actual service account

```bash
# Check role's trust policy
aws iam get-role --role-name <role-name> --query 'Role.AssumeRolePolicyDocument'
```

Compare the `Principal` field in trust policy to what's actually trying to assume.

### IRSA Specifically — Pod Can't Use the Role

Common debugging:

1. **Service account has the annotation?**
   ```bash
   kubectl describe sa auth-service-sa -n auth-namespace
   # Should show: eks.amazonaws.com/role-arn: arn:...
   ```

2. **Pod uses the service account?**
   ```bash
   kubectl describe pod <name> -n auth-namespace | grep "Service Account"
   ```

3. **Trust policy's `sub` matches exactly?**
   ```
   system:serviceaccount:<namespace>:<sa-name>
   
   For sa `auth-service-sa` in namespace `auth-namespace`:
   system:serviceaccount:auth-namespace:auth-service-sa
   ```

4. **OIDC provider is configured on the cluster?**
   ```bash
   aws eks describe-cluster --name kubecore-dev --query 'cluster.identity.oidc.issuer'
   aws iam list-open-id-connect-providers
   ```

5. **AWS SDK in the pod is recent enough?**
   - IRSA requires AWS SDK versions that support web identity tokens
   - Most modern SDKs (Java 2.x, Go v2, Python boto3 1.20+, JS v3) support it

---

## Glossary

**Action** — A specific AWS API call, formatted as `service:OperationName` (e.g., `s3:GetObject`).

**ARN** — Amazon Resource Name. Unique identifier for an AWS resource. Format: `arn:aws:service:region:account:resource`.

**AssumeRole** — The act of obtaining temporary credentials for a role. The STS API call: `sts:AssumeRole`.

**AWS-Managed Policy** — A policy maintained by AWS, attachable to any role/user. Example: `AmazonEKSClusterPolicy`.

**Condition** — Optional constraints in a policy statement (e.g., "only from this IP" or "only for resources with this tag").

**Customer-Managed Policy** — A policy you create, reusable across roles/users.

**Effect** — Either `Allow` or `Deny` in a policy statement.

**Federated Identity** — A user who authenticates with an external IdP and gets temporary AWS credentials.

**Group** — An IAM construct holding multiple users with shared policies. Largely superseded by roles.

**IAM** — Identity and Access Management. The AWS service for managing identities and permissions.

**Inline Policy** — A policy embedded directly in a role/user, not reusable.

**Instance Profile** — A container that lets an EC2 instance use a role. Required because EC2 doesn't reference roles directly.

**IRSA** — IAM Roles for Service Accounts. Pattern for giving EKS pods IAM permissions.

**Managed Policy** — Catch-all for AWS-managed and customer-managed policies (not inline).

**OIDC** — OpenID Connect. The protocol used for federated authentication, including IRSA and GitHub Actions OIDC.

**Permission Policy** — A policy attached to a role/user defining what they can do.

**Pod Identity** — Newer alternative to IRSA. Conceptually similar.

**Principal** — The "who" in IAM. Can be a service, user, role, account, or federated identity.

**Resource Policy** — A policy attached to a resource (not an identity) defining who can access it.

**Role** — A temporary identity with no long-term credentials, assumed by trusted entities.

**SCP** — Service Control Policy. Organization-level policy that can deny actions across all accounts.

**Service-Linked Role** — A role automatically created by an AWS service for its own use.

**Service Account** (Kubernetes) — A Kubernetes identity for pods. With IRSA, it's annotated with an IAM role ARN.

**STS** — Security Token Service. AWS service that issues temporary credentials.

**Trust Policy** — A policy attached to a role defining who can assume it.

**User** — A long-lived IAM identity for a specific person or system.

---

## References

- [IAM User Guide](https://docs.aws.amazon.com/IAM/latest/UserGuide/introduction.html)
- [IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [Policy Evaluation Logic](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html)
- [Policy Simulator](https://policysim.aws.amazon.com)
- [IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [EKS Best Practices — Identity](https://aws.github.io/aws-eks-best-practices/security/docs/iam/)
- [AWS Managed Policies Reference](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_managed-vs-inline.html)

---

_Last updated: 2026-06-15_
_Living document — extend as you encounter new patterns._
