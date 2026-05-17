#!/usr/bin/env bash
set -euo pipefail

# ---- config ----
CLUSTER_NAME="vanguard"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(dirname "$SCRIPT_DIR")"

KIND_CONFIG="$BOOTSTRAP_DIR/kind/cluster.yaml"
ARGOCD_INSTALL="$BOOTSTRAP_DIR/argocd/install.yaml"
ROOT_APP="$BOOTSTRAP_DIR/argocd/root-app.yaml"

# ---- preflight: required binaries ----
for cmd in kind kubectl docker; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: '$cmd' is not installed or not on PATH"
    exit 1
  fi
done

# ---- preflight: required files ----
for f in "$KIND_CONFIG" "$ARGOCD_INSTALL" "$ROOT_APP"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: required file not found: $f"
    exit 1
  fi
done

# ---- preflight: docker daemon reachable ----
if ! docker info >/dev/null 2>&1; then
  echo "ERROR: docker daemon is not reachable. Is Docker Desktop running?"
  exit 1
fi

# ---- preflight: cluster does not already exist ----
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "ERROR: kind cluster '${CLUSTER_NAME}' already exists."
  echo "  Delete it first: kind delete cluster --name ${CLUSTER_NAME}"
  exit 1
fi

# ---- create cluster ----
echo "==> Creating kind cluster: $CLUSTER_NAME"
kind create cluster --name "$CLUSTER_NAME" --config "$KIND_CONFIG"

echo "==> Waiting for nodes to be Ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# ---- install argocd ----
echo "==> Installing ArgoCD (from pinned local manifest)"
kubectl get namespace argocd >/dev/null 2>&1 || kubectl create namespace argocd
kubectl apply -n argocd -f "$ARGOCD_INSTALL"

echo "==> Waiting for ArgoCD components to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment --all -n argocd

# ---- bootstrap root app ----
echo "==> Applying root Application (app-of-apps)"
kubectl apply -f "$ROOT_APP"

# ---- done ----
cat <<EOF

==> Bootstrap complete.

To access the ArgoCD UI:
  1. Get the initial admin password:
       kubectl -n argocd get secret argocd-initial-admin-secret \\
         -o jsonpath='{.data.password}' | base64 -d; echo
  2. Port-forward the server:
       kubectl port-forward svc/argocd-server -n argocd 8080:443
  3. Open https://localhost:8080
       Username: admin

To watch the platform come up:
  kubectl get applications -n argocd -w

To tear down:
  kind delete cluster --name ${CLUSTER_NAME}
EOF