#!/bin/bash
echo "🚀 Starting KubeCore Multi-Node Infrastructure..."
minikube start --nodes 2 --memory 4096 --cpus 2 --driver=docker
echo "✅ Cluster is ready. Nodes online:"
kubectl get nodes
