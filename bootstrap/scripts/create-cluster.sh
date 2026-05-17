#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="vanguard"
CONFIG_PATH="$(dirname "$0")/../kind/kind-config.yaml"

echo "Creating kind cluster: $CLUSTER_NAME"
kind create cluster --name "$CLUSTER_NAME" --config "$CONFIG_PATH"

echo "Installing ArgoCD"
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

echo "Bootstrapping the root ArgoCD Application (app of apps)"
kubectl apply -f "$(dirname "$0")/../argocd-bootstrap/root-app.yaml"

echo "Done. Get ArgoCD password with:"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"