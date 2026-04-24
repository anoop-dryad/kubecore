# KubeCore

**KubeCore** is an infrastructure-focused laboratory designed to demonstrate the fundamental patterns of Kubernetes orchestration. This project focuses on the "plumbing" of a cluster: how configuration, shared storage, and multi-container coordination function within a distributed system.

---

## 🏗 Project Architecture

KubeCore is structured to move beyond simple deployments, focusing on the mechanics of self-healing and dynamic updates.



### Core Objectives
* **Config Decoupling:** Managing application behavior via ConfigMaps without rebuilding images.
* **Volume Plumbing:** Mastering the relationship between `Volumes` (sources) and `VolumeMounts` (access points).
* **Sidecar Patterns:** Implementing inter-container communication using shared `emptyDir` volumes.
* **Multi-Node Sync:** Observing real-time configuration propagation across a distributed cluster.

---

## 📂 Directory Structure

```text
/kubecore
├── k8s/
│   ├── service-1/                  # Project A: Independent Service-1 System
│   │   ├── base/                   # Common templates (Deployment, Service)
│   │   │   ├── kustomization.yaml  # Links all base files together
│   │   │   ├── namespace.yaml
│   │   │   ├── configmap.yaml
│   │   └── overlays/               # Environment-specific overrides
│   │       ├── dev/                # Local/Minikube settings
│   │       └── prod/               # Cloud/Production settings
│   │
│   ├── service-2/                  # Project B: Independent Service-2 System
│   │   ├── base/                   # Common templates
│   │   │   ├── kustomization.yaml  # Links all base files together
│   │   │   ├── namespace.yaml
│   │   │   ├── configmap.yaml
│   │   └── overlays/               # Environment-specific overrides
│   │       ├── dev/
│   │       └── prod/
│   │
│   └── platform-infra/             # Shared Cluster Resources
│       └── base/                   # Namespaces, Traefik Middlewares, RBAC
│
├── scripts/                        # Automation & Orchestration
│   ├── setup-cluster.sh            # Provisions Multi-Node Minikube
│   ├── deploy-auth.sh              # Deploys Auth Project only
│   └── deploy-data.sh              # Deploys Data Project only
│
├── README.md                       # Documentation & Architecture Labs
└── .gitignore                      # Protection for local/sensitive files
```

## 🚀 Getting Started

### 1. Provision the Infrastructure
To truly observe multi-node behavior, use the provided setup script. This ensures the cluster has enough resources and nodes to demonstrate distributed configuration syncing.

```bash
chmod +x scripts/start-cluster.sh
./scripts/start-cluster.sh
```

### 🗑 Cleanup
To shut down the infrastructure and free up your system resources:
```bash
minikube stop
# Or to delete everything:
minikube delete -p kubecore
```
