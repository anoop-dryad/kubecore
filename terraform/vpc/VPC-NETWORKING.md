# VPC Networking — Complete Reference

> Personal reference for understanding AWS VPC networking, EKS requirements, and the kubecore VPC module. Read top-to-bottom on first encounter; use as a lookup later.

---

## Table of Contents

1. [Foundations — IP Addresses and CIDR](#foundations--ip-addresses-and-cidr)
2. [What is a VPC](#what-is-a-vpc)
3. [Subnets](#subnets)
4. [Public vs Private Subnets](#public-vs-private-subnets)
5. [Routing — How Traffic Moves](#routing--how-traffic-moves)
6. [Internet Gateway](#internet-gateway)
7. [NAT Gateway](#nat-gateway)
8. [Security Groups](#security-groups)
9. [NACLs (Network Access Control Lists)](#nacls)
10. [EKS-Specific Networking Requirements](#eks-specific-networking-requirements)
11. [The kubecore VPC — Architecture](#the-kubecore-vpc--architecture)
12. [Traffic Flow Walkthroughs](#traffic-flow-walkthroughs)
13. [Common Patterns and When to Use Them](#common-patterns)
14. [Decision Checklists](#decision-checklists)
15. [Troubleshooting](#troubleshooting)
16. [Glossary](#glossary)

---

## Foundations — IP Addresses and CIDR

Before VPCs make sense, you need to understand the addressing system.

### IP Address Refresher

Every device on a network needs a unique address. IPv4 addresses look like:

```
10.0.1.42
```

Four numbers (0-255 each), dotted. That's 4 bytes = 32 bits = ~4.3 billion possible addresses.

### CIDR Notation — How We Talk About Ranges

CIDR (Classless Inter-Domain Routing) lets us describe a **range of addresses**:

```
10.0.0.0/16
```

The `/16` means "the first 16 bits are fixed, the remaining 16 bits vary."

- `10.0.0.0/16` contains all addresses from `10.0.0.0` to `10.0.255.255` → 65,536 addresses
- `10.0.1.0/24` contains `10.0.1.0` to `10.0.1.255` → 256 addresses
- `10.0.1.5/32` is just one address — `10.0.1.5`

**Mental shortcut**: `/X` where X is bigger = smaller range.

| CIDR | Addresses | When used |
|---|---|---|
| `/8` | 16,777,216 | Massive corporate networks, not VPCs |
| `/16` | 65,536 | Typical VPC |
| `/20` | 4,096 | Large subnet |
| `/24` | 256 | Typical subnet (~251 usable after AWS reservations) |
| `/28` | 16 | Tiny subnet |
| `/32` | 1 | Single host |

### Private vs Public Address Ranges

The internet routes "public" IP addresses. Some ranges are **reserved for private networks** and never appear on the public internet:

```
10.0.0.0/8          → 10.0.0.0    to 10.255.255.255    (~16.7M addresses)
172.16.0.0/12       → 172.16.0.0  to 172.31.255.255    (~1M addresses)
192.168.0.0/16      → 192.168.0.0 to 192.168.255.255   (~65K addresses)
```

You **must** use one of these for your VPC. The kubecore VPC uses `10.0.0.0/16` because it's the largest and most common.

### Why CIDR Sizing Matters

- **Too small**: you run out of IPs as your app grows. Adding subnets later is messy.
- **Too large**: wasteful, harder to peer with other VPCs without overlap.

**Convention**: `/16` for VPC, `/24` for subnets. Gives you 256 possible subnets per VPC, 251 usable IPs per subnet. Almost always enough.

### AWS Reserves 5 IPs Per Subnet

When you create a `/24` subnet (256 addresses), only **251 are usable**. AWS reserves:

- `.0` — network identifier
- `.1` — VPC router
- `.2` — DNS server
- `.3` — reserved for future use
- `.255` — broadcast (not actually used on AWS, but reserved)

For a `10.0.1.0/24` subnet, usable IPs are `10.0.1.4` through `10.0.1.254`.

---

## What is a VPC

A **VPC (Virtual Private Cloud)** is your private, isolated network inside AWS. Think of it as your own datacenter, virtually.

### Mental Model

```
AWS Region (e.g. eu-central-1, "Frankfurt")
│
├── Your VPC (10.0.0.0/16)           ← isolated from other VPCs, even your own
│   ├── Your subnets
│   ├── Your routing rules
│   ├── Your firewalls
│   └── Your resources (EC2, RDS, etc.)
│
├── Other VPCs in your account       ← can't see each other without peering
│
└── Other AWS customers' VPCs        ← completely invisible to you
```

### Why VPCs Exist

Before VPCs, AWS had EC2-Classic — everyone's instances shared one big network. Total isolation between accounts didn't exist. VPCs solved this: every account gets fully isolated networks.

### VPC Properties

When you create a VPC, you specify:

- **CIDR block**: the address range (e.g. `10.0.0.0/16`)
- **Region**: which AWS region it lives in (a VPC is region-scoped)
- **DNS settings**: whether internal DNS resolution works

You can have **multiple VPCs** per region (default limit: 5, raisable).

### A VPC Spans an Entire Region

This is important. A VPC isn't tied to a single Availability Zone — it spans all AZs in its region. **Subnets** are what bind to specific AZs (next section).

```
VPC: eu-central-1 (Frankfurt region)
├── Subnet in eu-central-1a
├── Subnet in eu-central-1b
└── Subnet in eu-central-1c
```

All three subnets are in the same VPC, even though they're in different AZs.

---

## Subnets

A **subnet** is a slice of your VPC's address space, tied to a specific Availability Zone.

### Why Split a VPC Into Subnets

Three reasons:

**1. Availability Zone placement.** Subnets are AZ-bound. To run resources in multiple AZs (for HA), you need multiple subnets — one per AZ. EKS specifically requires at least 2 AZs.

**2. Traffic isolation.** Different subnets can have different routing rules. Public-facing things go in one subnet, internal things in another.

**3. Security boundaries.** Subnets are a natural boundary for security policies (NACLs operate at subnet level).

### Subnet Sizing

A subnet's CIDR is a subset of the VPC's CIDR:

```
VPC:               10.0.0.0/16        (65,536 addresses)
├── Subnet 1:      10.0.1.0/24        (256 addresses, AZ-a)
├── Subnet 2:      10.0.2.0/24        (256 addresses, AZ-b)
├── Subnet 3:      10.0.11.0/24       (256 addresses, AZ-a)
└── Subnet 4:      10.0.12.0/24       (256 addresses, AZ-b)
```

Note: subnet CIDRs **must not overlap**. If subnet 1 is `10.0.1.0/24`, subnet 2 can be `10.0.2.0/24` (no overlap) but not `10.0.1.0/24` (collision).

### Subnet Naming Convention

A common pattern: `<env>-<purpose>-<az>`:

```
dev-kubecore-public-eu-central-1a
dev-kubecore-public-eu-central-1b
dev-kubecore-private-eu-central-1a
dev-kubecore-private-eu-central-1b
```

This makes subnets self-documenting in the AWS Console.

---

## Public vs Private Subnets

The terms "public" and "private" aren't AWS settings you flip — they're properties that emerge from **routing configuration**.

### The Defining Property

- **Public subnet**: has a route to the Internet Gateway (`0.0.0.0/0 → IGW`)
- **Private subnet**: does NOT have a route to the Internet Gateway

That's literally the only difference. Same VPC, same address space rules, same AWS APIs — the routing tables tell you which is which.

### What Goes In Each

**Public subnet — for resources that must accept inbound internet traffic:**

| Resource | Why |
|---|---|
| Application Load Balancer (ALB) | Receives HTTPS from users |
| Network Load Balancer (NLB) | Receives TCP from users |
| NAT Gateway | Provides outbound internet for private subnets |
| Bastion host | SSH entry point (if used) |
| VPN endpoint | Allows secure access into the VPC |

**Private subnet — for everything else:**

| Resource | Why |
|---|---|
| EKS worker nodes | Pods shouldn't be directly internet-reachable |
| EC2 application servers | Same |
| RDS database | Critical data, never expose |
| ElastiCache | Cache data, often sensitive |
| Internal microservices | Service-to-service traffic only |

### The Big Misconception

"Private subnet means no internet at all" — **wrong**.

Private means **no inbound from internet**. Resources can still make **outbound** calls if you set up NAT (more on that below).

A private EC2 instance can:
- ✅ Call `api.stripe.com` (outbound) — IF NAT is configured
- ✅ Pull a Docker image from ECR — IF NAT or VPC endpoints
- ❌ Receive an unsolicited connection from the internet — never

That asymmetry is the whole security benefit.

---

## Routing — How Traffic Moves

When a packet leaves a resource in your VPC, it needs to know **where to go**. That's what route tables do.

### Route Table Basics

A route table is a list of rules:

```
Destination          Target
10.0.0.0/16          local              ← traffic within VPC stays in VPC
0.0.0.0/0            igw-abc123         ← everything else goes to Internet Gateway
```

Each subnet is **associated with exactly one route table**. The route table determines where the subnet's traffic can go.

### The "Local" Route

Every route table has an implicit "local" route covering the VPC's CIDR. You can't remove it. It's how subnets within the same VPC can talk to each other without going through any gateway.

### Route Matching — Most Specific Wins

If a packet matches multiple routes, the **most specific** wins:

```
10.0.0.0/16          local              ← VPC traffic
10.0.5.0/24          vpc-peering-abc    ← traffic for one specific subnet via peering
0.0.0.0/0            igw-abc123         ← catch-all
```

A packet to `10.0.5.42` matches all three, but uses the `/24` rule because it's most specific.

### Default Route (0.0.0.0/0)

The "default route" or "catch-all" route is `0.0.0.0/0`. It matches **anything** not matched by a more specific rule. Typically pointed at:

- **Internet Gateway** (public subnet)
- **NAT Gateway** (private subnet)
- **VPN/Direct Connect** (corporate networks)

### Multiple Route Tables Per VPC

Common pattern: separate route tables for public and private subnets.

```
Public route table:
  10.0.0.0/16  → local
  0.0.0.0/0    → IGW                    ← public subnets get this

Private route table:
  10.0.0.0/16  → local
  0.0.0.0/0    → NAT Gateway            ← private subnets get this
```

Same VPC, different routing depending on subnet. The kubecore VPC does this.

---

## Internet Gateway

The **Internet Gateway (IGW)** is the door between your VPC and the public internet.

### Properties

- **One per VPC** (one is enough)
- **Free** — no hourly cost
- **Horizontally scaled, redundant** — handled by AWS
- **Required for any internet-facing resource**

### How It Works

The IGW does two things:

1. **NAT for resources with public IPs**: when a resource in a public subnet talks to the internet, the IGW translates between the resource's public IP and the actual outbound traffic.
2. **Allows inbound** traffic to resources with public IPs.

### When You Need It

Any time your VPC has resources that need internet access (in either direction), the VPC needs an IGW. Even if all your internet-bound traffic flows through NAT, the NAT itself needs the IGW.

### Diagram

```
Internet
   ↑↓
[Internet Gateway]
   ↑↓
VPC
├── Public subnet
│   ├── ALB (has public IP)             ←→ Internet via IGW
│   └── NAT Gateway (has public IP)     ←→ Internet via IGW
└── Private subnet
    └── App server (no public IP)        → can reach internet only via NAT
```

---

## NAT Gateway

The **NAT (Network Address Translation) Gateway** lets resources in private subnets make outbound connections to the internet while remaining unreachable from inbound traffic.

### Why You Need It

Even private resources usually need outbound internet access:

- Pull container images (Docker Hub, ECR)
- Call external APIs (Stripe, SendGrid)
- Download OS updates
- Communicate with AWS services (S3, Secrets Manager) — unless using VPC endpoints

Without NAT (or VPC endpoints), your private resources can't do any of this. Pods stuck in `ImagePullBackOff`. App can't process payments. Logs fail to ship.

### How It Works

```
Private EC2 instance (10.0.11.45)
   │
   │ Wants to reach api.stripe.com
   │
   ▼
Route table says: 0.0.0.0/0 → NAT Gateway
   │
   ▼
NAT Gateway (in public subnet, has public IP 52.x.x.x)
   │
   │ NAT does the translation:
   │   - Outbound: request appears to come from 52.x.x.x (NAT's public IP)
   │   - Inbound response: NAT remembers "this is for 10.0.11.45" and forwards
   │
   ▼
Internet Gateway → Stripe servers

Stripe replies → IGW → NAT Gateway → 10.0.11.45
```

Crucial property: **NAT only forwards responses to outbound connections the private resource initiated**. Stripe can't initiate a connection to your private resource. That's the security win.

### Properties

- **Costs ~$32/month per NAT Gateway** (24/7) + data transfer at $0.045/GB
- **One NAT serves multiple private subnets** (typically one route table for all private subnets)
- **High availability**: a single NAT is a single point of failure. For HA, one NAT per AZ (3x the cost).
- **Requires an Elastic IP** (a static public IP) attached to it

### When to Skip NAT

Three scenarios where you might not need NAT:

1. **Nodes in public subnets**: less secure but works. Some hobby projects do this.
2. **VPC Endpoints**: AWS services like ECR, S3, Secrets Manager can be accessed via VPC endpoints that don't go through the internet. ~$7/month per endpoint, but you might need 5-10. Total: comparable to NAT cost.
3. **Pure-internal apps**: if your app truly never makes outbound calls, you don't need NAT. Very rare in practice — even logs and metrics usually need outbound.

### Multi-AZ NAT

```
Production HA setup:
  AZ-a:  NAT Gateway → private subnet AZ-a
  AZ-b:  NAT Gateway → private subnet AZ-b
  AZ-c:  NAT Gateway → private subnet AZ-c

Cost: 3 × $32 = $96/month, but no single point of failure.

Dev/cost-conscious setup:
  AZ-a:  NAT Gateway → all private subnets (AZ-a AND AZ-b)

Cost: $32/month, but if AZ-a fails, AZ-b's private subnet loses internet.
```

For dev: single NAT. For prod: one per AZ.

---

## Security Groups

A **Security Group (SG)** is a **stateful firewall** that operates at the **resource level** (per ENI, technically).

### Key Properties

- **Stateful**: if you allow outbound, the return traffic is automatically allowed. No need to add an inbound rule for responses.
- **Resource-level**: SGs are attached to ENIs (Elastic Network Interfaces), which are attached to EC2 instances, RDS, ALBs, etc.
- **Allow-only**: you can only ADD allow rules. There's no "deny" — if no rule allows the traffic, it's blocked.
- **One resource can have multiple SGs**: their rules are combined (union).

### Anatomy of an SG Rule

```
Direction: Ingress (inbound) or Egress (outbound)
Protocol:  TCP / UDP / ICMP / All (-1)
Port:      Single port (443) or range (1025-65535)
Source/Destination:
  - CIDR (e.g. 0.0.0.0/0)
  - Another SG (referenced by ID)
  - Prefix list (AWS-managed list of IPs for a service)
```

### Stateful Explained

Stateful means SGs remember outbound connections and auto-allow the return:

```
Pod (SG-A) sends request to External API on port 443
   ↓
   Egress rule on SG-A: "Allow outbound to 0.0.0.0/0 on 443" → ALLOW
   ↓
   External API responds
   ↓
   No explicit ingress rule needed — SG auto-allows because it tracks the connection

Compare with NACL (stateless):
   Egress rule: allow outbound 443
   Ingress rule: allow inbound on EPHEMERAL ports (1024-65535) — required separately for response
```

Stateful is **much easier** to configure correctly. NACLs being stateless is why they're notoriously hard to debug.

### Default SG Behavior

When you create an SG:

- **Ingress**: nothing allowed by default (must add rules)
- **Egress**: ALL allowed by default (you can remove if you want strict outbound)

When you create an EC2 (or other resource) without specifying an SG, it gets the VPC's default SG, which has open intra-SG communication.

### Referencing Other SGs vs CIDRs

Two ways to specify the source/destination:

**CIDR-based** (less safe):
```
Allow ingress from 10.0.0.0/16 on port 443
```
Anyone in that IP range can connect. If someone else spins up an EC2 in the same VPC, they qualify.

**SG-based** (preferred):
```
Allow ingress from sg-app-server-abc on port 443
```
Only resources in the `app-server` SG can connect. More granular, more secure.

Pattern: use SG references for intra-VPC traffic, CIDR for cross-VPC or external.

### EKS SG Pattern

EKS uses three security groups typically:

1. **Cluster SG**: attached to the EKS control plane's ENIs (managed by AWS)
2. **Worker SG**: attached to all worker nodes
3. **Auto-created LB SG**: AWS auto-creates one per LoadBalancer service

Rules between them:

```
Worker → Cluster on 443     ← workers call EKS API
Cluster → Worker 1025-65535  ← control plane to kubelet, webhooks
Worker ↔ Worker any port     ← pod-to-pod traffic
```

The kubecore VPC module creates SGs 1 and 2 with these rules.

### The `ignore_changes = [ingress]` Pattern for Worker SG

```hcl
resource "aws_security_group" "eks_worker" {
  # ...
  lifecycle {
    ignore_changes = [ingress]
  }
}
```

EKS dynamically adds ingress rules to the worker SG when you create LoadBalancer services. If Terraform tries to "correct" these on next apply, it removes them, breaking the LB. The `ignore_changes` tells Terraform "leave ingress alone."

---

## NACLs

A **NACL (Network Access Control List)** is a **stateless firewall** that operates at the **subnet level**.

### Why NACLs Exist

NACLs are the older firewall layer in AWS. They predate Security Groups. They give you subnet-wide controls.

### Key Differences from SGs

| Aspect | Security Group | NACL |
|---|---|---|
| Stateful? | Yes (auto-allow returns) | No (must allow both directions) |
| Level | Per-resource (ENI) | Per-subnet |
| Allow + Deny? | Allow only | Both allow and deny |
| Order matters? | No (all rules evaluated) | Yes (lower rule number = higher priority) |
| Default behavior | Deny inbound, allow outbound | Allow all (default NACL) or deny all (custom) |

### When to Use NACLs

**Honest answer: rarely.** Most production AWS setups leave NACLs at their default (allow all) and rely on Security Groups for access control.

Reasons to bother with NACLs:

1. **Block specific IPs** at the subnet level (e.g., known-bad CIDRs from threat intel)
2. **Defense-in-depth** for compliance requirements
3. **Subnet-wide policies** that would be tedious to apply per-SG

### Common Mistake

People try to use NACLs the way they use SGs and get confused why traffic is blocked. NACL stateless behavior means:

```
Want: allow ALB → backend on port 80

Wrong (typical SG-thinking):
  Ingress rule: allow 80 from ALB

Right:
  Ingress rule: allow 80 from ALB
  Egress rule:  allow ephemeral ports (1024-65535) back to ALB ← response traffic
```

If you forget the egress side, requests reach your backend but responses get blocked, and you spend an hour debugging "intermittent timeouts."

### The kubecore Pattern

We **don't define custom NACLs**. AWS's default NACL is wide-open (allow all in both directions). Security Groups do all our access control. This is the standard production pattern.

---

## EKS-Specific Networking Requirements

EKS has specific requirements that drive VPC design.

### Required VPC Settings

- **`enable_dns_hostnames = true`** — EC2 instances get DNS names like `ip-10-0-1-5.eu-central-1.compute.internal`
- **`enable_dns_support = true`** — internal DNS resolution works within the VPC

Without both, EKS won't function.

### Subnet Requirements

- **At least 2 AZs** — EKS spreads the control plane across multiple AZs for HA
- **At least one subnet (public or private) per AZ** — for worker nodes
- **Public subnets** required if you want public-facing load balancers

### EKS Auto-Discovery Tags

EKS looks at subnet tags to decide where to place load balancers. These tags **must** be present:

```
# On the VPC and ALL subnets:
"kubernetes.io/cluster/<cluster-name>" = "shared"  # or "owned"
```

```
# On PUBLIC subnets (for internet-facing LBs):
"kubernetes.io/role/elb" = "1"
```

```
# On PRIVATE subnets (for internal-only LBs):
"kubernetes.io/role/internal-elb" = "1"
```

When a Kubernetes user creates a `Service` of type `LoadBalancer`, EKS scans subnets, finds ones with `kubernetes.io/role/elb`, and provisions an ALB there.

### Subnet Sizing for EKS

Each pod gets its own IP from the worker node's subnet (assuming the VPC CNI plugin, which is the default). A node running 30 pods consumes 30 IPs from the subnet (plus its own).

**Rough sizing formula:**
```
IPs needed per subnet ≈ (nodes per AZ) × (pods per node) × buffer
```

For a small cluster: 10 nodes × 30 pods × 2x buffer = ~600 IPs. A `/24` subnet (251 usable) might be too tight. A `/22` (1019 usable) gives breathing room.

For kubecore dev: `/24` is fine — we're running 2-3 nodes max.

### Outbound Internet for Pods

Pods need outbound internet for:
- Pulling container images (especially from non-ECR registries)
- Calling external APIs
- Communicating with AWS services (if not using VPC endpoints)
- DNS resolution to external domains

Without NAT or VPC endpoints, pods can't pull images. Cluster never becomes functional.

---

## The kubecore VPC — Architecture

Here's what the kubecore VPC module creates.

### Visual Layout

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          AWS Region: eu-central-1                           │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                 VPC: dev-kubecore-vpc  (10.0.0.0/16)                  │  │
│  │                                                                       │  │
│  │  ┌──────────────────────────┐    ┌──────────────────────────┐         │  │
│  │  │   eu-central-1a          │    │   eu-central-1b          │         │  │
│  │  │                          │    │                          │         │  │
│  │  │  ┌────────────────────┐  │    │  ┌────────────────────┐  │         │  │
│  │  │  │ Public Subnet      │  │    │  │ Public Subnet      │  │         │  │
│  │  │  │ 10.0.1.0/24        │  │    │  │ 10.0.2.0/24        │  │         │  │
│  │  │  │                    │  │    │  │                    │  │         │  │
│  │  │  │ Future: ALB, NAT   │  │    │  │ Future: ALB        │  │         │  │
│  │  │  └────────────────────┘  │    │  └────────────────────┘  │         │  │
│  │  │           │              │    │           │              │         │  │
│  │  │           │              │    │           │              │         │  │
│  │  │  ┌────────────────────┐  │    │  ┌────────────────────┐  │         │  │
│  │  │  │ Private Subnet     │  │    │  │ Private Subnet     │  │         │  │
│  │  │  │ 10.0.11.0/24       │  │    │  │ 10.0.12.0/24       │  │         │  │
│  │  │  │                    │  │    │  │                    │  │         │  │
│  │  │  │ Future: EKS nodes  │  │    │  │ Future: EKS nodes  │  │         │  │
│  │  │  │ Future: RDS        │  │    │  │                    │  │         │  │
│  │  │  └────────────────────┘  │    │  └────────────────────┘  │         │  │
│  │  │                          │    │                          │         │  │
│  │  └──────────────────────────┘    └──────────────────────────┘         │  │
│  │                                                                       │  │
│  │              ┌─────────────────────────────┐                          │  │
│  │              │   Internet Gateway          │                          │  │
│  │              │   (attached to VPC)         │                          │  │
│  │              └─────────────────────────────┘                          │  │
│  │                          ▲                                            │  │
│  └──────────────────────────┼────────────────────────────────────────────┘  │
│                             │                                               │
└─────────────────────────────┼───────────────────────────────────────────────┘
                              │
                              ▼
                          Internet
```

### Routing

```
Public Route Table:
  10.0.0.0/16  → local                ← traffic within VPC
  0.0.0.0/0    → Internet Gateway     ← everything else

  Associated subnets:
    - dev-kubecore-public-eu-central-1a
    - dev-kubecore-public-eu-central-1b

Private Route Table:
  10.0.0.0/16  → local                ← traffic within VPC
  (no 0.0.0.0/0 route — no internet yet)

  Associated subnets:
    - dev-kubecore-private-eu-central-1a
    - dev-kubecore-private-eu-central-1b
```

### Security Groups

```
dev-kubecore-eks-cluster-sg
├── Egress: allow all outbound
└── Ingress:
    └── From dev-kubecore-eks-worker-sg on port 443 (kubectl, kubelet)

dev-kubecore-eks-worker-sg
├── Egress: allow all outbound
└── Ingress:
    ├── From dev-kubecore-eks-cluster-sg on ports 1025-65535 (control plane callbacks)
    └── From dev-kubecore-eks-worker-sg on all ports (pod-to-pod)

    Note: EKS will dynamically add more ingress rules when LoadBalancer
    services are created. The lifecycle.ignore_changes = [ingress] tells
    Terraform not to fight EKS.
```

### What's NOT There Yet

```
✗ NAT Gateway          — adds $32/month, not needed until EKS workloads exist
✗ Elastic IP           — needed for NAT Gateway
✗ Private route to NAT — needed for NAT Gateway
✗ VPC endpoints        — alternative to NAT for AWS-service-only traffic
```

When you add EKS and need outbound internet:
1. Add NAT Gateway resource
2. Add EIP resource
3. Add route in private route table: `0.0.0.0/0 → NAT Gateway`

That's it. Three additional resources. Cost: $32/month.

---

## Traffic Flow Walkthroughs

Concrete examples of how packets move through the architecture.

### Scenario 1: User Reaches Your App (Inbound)

A user opens `https://auth.example.com` in their browser.

```
[1] User → DNS lookup for auth.example.com
    Returns: 52.x.x.x (ALB's public IP)

[2] User → 52.x.x.x:443
    Packet enters AWS at the ALB

[3] ALB (in public subnet 10.0.1.0/24)
    - Terminates TLS
    - Picks a healthy auth-service pod from its target group
    - Forwards request to pod IP, e.g. 10.0.11.45:8081

[4] Pod (in private subnet 10.0.11.0/24)
    - Processes the request
    - Needs to query Postgres
    - Sends query to postgres.dev-kubecore.local:5432

[5] Postgres pod (in private subnet, 10.0.11.78)
    - Receives query (routed via VPC local route)
    - Returns data

[6] Pod → ALB (response, via VPC local route)

[7] ALB → User (via IGW)
```

Notice the public/private boundary: the ALB is the **only** thing the user's packet touches in a public subnet. Everything after is private.

### Scenario 2: Pod Calls External API (Outbound) — WITHOUT NAT

```
[1] Pod (10.0.11.45) wants to call api.stripe.com

[2] Pod's route table: private route table
    10.0.0.0/16 → local
    (no 0.0.0.0/0 route)

[3] Result: packet has no route. Pod gets "no route to host" error.

❌ This is why pure-private without NAT doesn't work for pods that need external internet.
```

### Scenario 3: Pod Calls External API — WITH NAT

```
[1] Pod (10.0.11.45) wants to call api.stripe.com

[2] Private route table:
    10.0.0.0/16 → local
    0.0.0.0/0   → NAT Gateway (in 10.0.1.0/24 public subnet)

[3] Packet routes to NAT Gateway
    NAT swaps source IP: 10.0.11.45 → 52.x.x.x (NAT's public IP)

[4] NAT → Internet Gateway → Stripe

[5] Stripe responds → IGW → NAT
    NAT remembers the mapping, swaps destination IP: 52.x.x.x → 10.0.11.45

[6] Pod receives response
```

### Scenario 4: External Connection Attempt to Private Pod

Someone tries to connect directly to a pod's IP from the internet.

```
[1] Attacker → 10.0.11.45:8081 (pod's "IP")

[2] But 10.0.11.45 is a private IP. It's not routable on the internet.
    The packet never leaves the attacker's local network.

❌ Connection fails. Pod is fundamentally unreachable from outside.

Even if you forwarded the IP somehow (you can't), the pod has no public IP.
The IGW only "knows" about resources with public IPs.
```

This is the core security property of private subnets. Pods aren't just firewalled from the internet — they're not even addressable from it.

### Scenario 5: Pod-to-Pod Communication Across AZs

```
[1] Pod A (10.0.11.45) in subnet 10.0.11.0/24 (AZ-a)
    wants to call Pod B (10.0.12.67) in subnet 10.0.12.0/24 (AZ-b)

[2] Pod A's route table: private route table
    10.0.0.0/16 → local

[3] Destination 10.0.12.67 matches 10.0.0.0/16. Routes locally.

[4] Packet travels through VPC infrastructure to Pod B.
    Crosses AZs internally — invisible to the application.

[5] Returns the same way.

✓ Works automatically because both subnets are in the same VPC.
✓ No latency penalty within a single region for typical workloads.
```

---

## Common Patterns

When you design future VPCs, these patterns cover ~90% of cases.

### Pattern A: Simple Public-Only (Hobby/Demo)

```
VPC (10.0.0.0/16)
├── 2 Public subnets
├── Internet Gateway
└── Single route table → IGW

Pros: free (no NAT), simple
Cons: everything is internet-exposed
Use when: pure learning, throwaway demos
```

### Pattern B: Public + Private, Single NAT (Dev / Cost-Conscious)

```
VPC (10.0.0.0/16)
├── 2 Public subnets
├── 2 Private subnets
├── 1 Internet Gateway
├── 1 NAT Gateway (in az-a only)
├── Public route table → IGW
└── Private route table → NAT

Pros: production-shape, ~$32/month
Cons: az-a outage = all private subnets lose internet
Use when: dev environments, small prod, cost-sensitive
```

### Pattern C: Public + Private, Multi-AZ NAT (Production)

```
VPC (10.0.0.0/16)
├── 3 Public subnets (one per AZ)
├── 3 Private subnets (one per AZ)
├── 1 Internet Gateway
├── 3 NAT Gateways (one per AZ)
├── Public route table → IGW
└── Private route tables (3, one per AZ) → respective NAT

Pros: HA, no single point of failure
Cons: ~$96/month for NATs
Use when: production, real users
```

### Pattern D: Private with VPC Endpoints (High Security)

```
VPC (10.0.0.0/16)
├── 2 Public subnets (only for ALB)
├── 2 Private subnets
├── 1 Internet Gateway (for ALB only)
├── VPC Endpoints (for AWS services: ECR, S3, Secrets Manager, etc.)
└── NO NAT Gateway

Pros: zero outbound internet for pods, most secure
Cons: ~$56/month for endpoints, can't reach non-AWS external APIs
Use when: regulated industries (healthcare, finance), compliance reqs
```

### Pattern E: Multi-VPC With Transit Gateway (Enterprise)

```
Account A:
  VPC 1 (10.0.0.0/16) ─┐
                       │
Account B:             │
  VPC 2 (10.1.0.0/16) ─┼──→ Transit Gateway ──→ Centralized Egress VPC
                       │                        ↓
Account C:             │                     NAT + Firewall
  VPC 3 (10.2.0.0/16) ─┘

Pros: centralized policy, shared services, scales to dozens of VPCs
Cons: complex, ~$36/month per VPC attachment + $0.02/GB
Use when: large orgs, compliance, audit requirements
```

---

## Decision Checklists

### Designing a New VPC — Decision Order

1. **Region**: which AWS region? (Lowest latency to users, data sovereignty laws, service availability)
2. **CIDR**: how many IPs? `/16` for most, `/20` for small, custom for special cases
3. **AZ count**: 2 minimum for EKS, 3 for full prod HA
4. **Subnet structure**: public + private? How many of each?
5. **Internet access for private resources**:
    - NAT Gateway (most flexible)
    - VPC Endpoints (AWS-only, more secure)
    - Both (most expensive, most flexible)
    - None (rare — strict offline workloads)
6. **HA requirements**: single NAT (cheap) or per-AZ NAT (HA)?
7. **VPC peering / Transit Gateway**: does this VPC need to talk to other VPCs?

### When to Add a NAT Gateway

✓ EKS pods that need to pull non-ECR images
✓ App needs to call external APIs (Stripe, SendGrid, etc.)
✓ App needs to download OS updates, certificates
✓ App needs CloudWatch Logs, S3, etc. (unless using VPC endpoints)

✗ Strictly internal app, no external dependencies, no AWS API calls
✗ Using VPC endpoints for all AWS services and no external APIs
✗ Pure learning where you've manually put things in public subnets

### Choosing Subnet Sizes for EKS

```
Pods per node × Nodes per AZ × Safety factor (2-3x) = IPs needed per subnet

Examples:
  30 pods × 5 nodes × 2 = 300 IPs → /24 (251 usable) tight, /23 (507) comfortable
  30 pods × 20 nodes × 3 = 1800 IPs → /21 (2043 usable) appropriate
  10 pods × 3 nodes × 2 = 60 IPs → /26 (59 usable) edge, /25 (123) safe
```

When in doubt, **size up**. Resizing subnets later requires recreating them.

### Choosing Between SG-Based and CIDR-Based Rules

```
Use SG references when:
  ✓ Source/destination is another AWS resource (EC2, RDS, etc.)
  ✓ You want granular control regardless of IPs
  ✓ The IPs of the source might change

Use CIDR when:
  ✓ Source/destination is outside the VPC
  ✓ You're restricting to a specific external network (e.g. office IP)
  ✓ You're allowing the entire internet (0.0.0.0/0)
```

---

## Troubleshooting

### "Connection times out" between two resources in the same VPC

Likely causes (in order of probability):

1. **Security group blocks the traffic**
   - Check the destination's SG: is there an ingress rule for the source?
   - Check protocol (TCP vs UDP) and port number
2. **NACL blocks the traffic** (stateless — both directions need rules)
3. **Subnets don't have routes to each other** — very rare in same VPC
4. **App isn't listening on the expected port** — `kubectl exec` into the pod and check

```bash
# Quick checks
kubectl get svc -n <namespace>          # confirm service IP
kubectl exec -it <pod> -- nc -zv <ip> <port>   # test connectivity
```

### "Cannot pull image" / ImagePullBackOff

Likely causes:

1. **No NAT Gateway** — pods can't reach Docker Hub/ECR
2. **No VPC endpoint** for ECR if using ECR Private
3. **Node IAM role missing ECR permissions** (need `AmazonEC2ContainerRegistryReadOnly`)
4. **Image actually doesn't exist** or tag is wrong

```bash
kubectl describe pod <name>             # see exact error
# If "no such host" → NAT/DNS issue
# If "403 Forbidden" → IAM/auth issue
```

### "Cluster is unhealthy" / nodes don't join cluster

Likely causes:

1. **Worker SG → Cluster SG rule missing on port 443** — workers can't reach EKS API
2. **Cluster SG → Worker SG ingress missing on 1025-65535** — control plane can't reach kubelets
3. **Subnets aren't tagged with `kubernetes.io/cluster/<name>`** — EKS doesn't recognize them
4. **Subnets in the wrong AZs** — EKS requires resources to be spread across AZs

### "Cannot reach external API from my pod"

Without NAT, this is expected. With NAT:

1. **Check route table for the pod's subnet** — is there `0.0.0.0/0 → NAT`?
2. **NAT Gateway in "Available" state?** — check Console
3. **NAT's Elastic IP attached?**
4. **VPC has Internet Gateway?** — NAT needs IGW to reach outside

```bash
# Inside a pod
kubectl exec -it <pod> -- curl -v https://api.stripe.com
# Connection refused → SG issue
# No route to host → routing/NAT issue
# Resolved IP but no response → security group ingress
```

### "Costs spiked from VPC"

Most common VPC cost surprises:

1. **NAT Gateway forgotten** — $32/month if left running
2. **Unattached Elastic IP** — $3.65/month per IP
3. **Inter-AZ data transfer** — $0.01/GB; significant if pods chatter across AZs heavily
4. **Cross-region traffic** — $0.02/GB; avoid if possible
5. **Public IPv4 addresses on instances** — $3.65/month each (since 2024)

```bash
# Check what's running
aws ec2 describe-nat-gateways --region eu-central-1 --query 'NatGateways[?State==`available`]'
aws ec2 describe-addresses --region eu-central-1 --query 'Addresses[?AssociationId==null]'
```

---

## Glossary

**ALB** — Application Load Balancer. Layer 7 (HTTP/HTTPS) load balancer.

**AZ** — Availability Zone. Physically separate datacenter within a region. Failures are isolated per-AZ.

**CIDR** — Classless Inter-Domain Routing. Notation for IP ranges like `10.0.0.0/16`.

**CNI** — Container Network Interface. The plugin that gives pods IP addresses. AWS VPC CNI is the EKS default.

**EIP** — Elastic IP. A static public IPv4 address. Free when attached to a running resource, ~$3.65/month otherwise.

**ENI** — Elastic Network Interface. A virtual network card. Every EC2 instance has at least one. Security Groups attach to ENIs.

**IGW** — Internet Gateway. The gateway between VPC and internet. Free, one per VPC, required for any internet access.

**IRSA** — IAM Roles for Service Accounts. EKS feature for giving Kubernetes pods IAM permissions.

**NACL** — Network Access Control List. Stateless subnet-level firewall. Usually left open in favor of SGs.

**NAT** — Network Address Translation. Lets private resources make outbound connections appearing as the NAT's public IP.

**NLB** — Network Load Balancer. Layer 4 (TCP/UDP) load balancer.

**SG** — Security Group. Stateful resource-level firewall. The primary access control mechanism in AWS.

**Subnet** — A range of IPs within a VPC, bound to a specific AZ.

**TGW** — Transit Gateway. Hub for connecting many VPCs (and on-prem networks).

**VPC** — Virtual Private Cloud. Your isolated network in AWS.

**VPC Endpoint** — A way to reach AWS services without internet. Two types: Gateway (free, S3/DynamoDB only) and Interface (~$7/month each).

**VPC Peering** — Direct connection between two VPCs. Routes one-to-one.

---

## References

- [AWS VPC User Guide](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html)
- [EKS Networking Requirements](https://docs.aws.amazon.com/eks/latest/userguide/network-reqs.html)
- [EKS Best Practices — Networking](https://aws.github.io/aws-eks-best-practices/networking/)
- [VPC CIDR Sizing Guide](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-cidr-blocks.html)
- [Security Groups vs NACLs](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Security.html)
- [Terraform AWS VPC Resources](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc)

---

_Last updated: 2026-06-14_
_Living document — extend as you encounter new patterns._
