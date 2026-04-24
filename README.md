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
│   ├── base/                  # The "Source of Truth" (Templates)
│   │   ├── kustomization.yaml # Links all base files together
│   │   ├── namespace.yaml
│   │   ├── configmap.yaml
│   │   ├── web-app.yaml       # Moved from workloads/ to base/
│   │   ├── backend.yaml       # Moved from workloads/ to base/
│   │   └── service.yaml       # Moved from networking/ to base/
│   └── overlays/              # The "Environment Tweaks"
│       ├── dev/
│       │   ├── kustomization.yaml
│       │   └── cm-patch.yaml  # e.g., Set color to 'blue' for Dev
│       └── prod/
│           ├── kustomization.yaml
│           └── replica-patch.yaml # e.g., Scale to 5 replicas for Prod
├── scripts/
│   ├── setup-cluster.sh
│   └── update-config.sh
├── README.md
└── .gitignore
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
