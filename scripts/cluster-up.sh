#!/usr/bin/env bash
# Crée le cluster local "taskvault" (idempotent).
set -euo pipefail
cd "$(dirname "$0")/.."

for tool in docker kind kubectl; do
  command -v "$tool" >/dev/null || { echo "Outil manquant : $tool" >&2; exit 1; }
done
docker info >/dev/null 2>&1 || { echo "Le moteur Docker ne répond pas : démarre Docker Desktop." >&2; exit 1; }

if kind get clusters | grep -qx taskvault; then
  echo "Cluster 'taskvault' déjà présent."
else
  kind create cluster --config cluster/kind-config.yaml
fi
kubectl --context kind-taskvault get nodes
