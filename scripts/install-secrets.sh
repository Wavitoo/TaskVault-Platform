#!/usr/bin/env bash
# Installe Vault (mode dev) et External Secrets Operator, configure Vault, puis crée les ExternalSecret.
set -euo pipefail
cd "$(dirname "$0")/.."
helm repo add hashicorp https://helm.releases.hashicorp.com >/dev/null 2>&1 || true
helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
helm repo update hashicorp external-secrets >/dev/null
helm upgrade --install vault hashicorp/vault --version 0.34.1 -n vault --create-namespace \
  -f k8s/vault/values.yaml --wait --timeout 5m
helm upgrade --install external-secrets external-secrets/external-secrets --version 2.15.0 \
  -n external-secrets --create-namespace -f k8s/external-secrets/values.yaml --wait --timeout 5m
kubectl apply -f k8s/base/namespace.yaml
./scripts/configure-vault.sh
kubectl apply -k k8s/secrets
kubectl -n taskvault wait --for=condition=Ready externalsecret/taskvault-db externalsecret/taskvault-app --timeout=120s
