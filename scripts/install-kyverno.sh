#!/usr/bin/env bash
# Installe Kyverno (Helm, version épinglée). La politique de vérification des images est déployée par Argo CD.
set -euo pipefail
cd "$(dirname "$0")/.."
helm repo add kyverno https://kyverno.github.io/kyverno >/dev/null 2>&1 || true
helm repo update kyverno >/dev/null
helm upgrade --install kyverno kyverno/kyverno --version 3.10.0 -n kyverno --create-namespace \
  -f k8s/kyverno/values.yaml --wait --timeout 5m
