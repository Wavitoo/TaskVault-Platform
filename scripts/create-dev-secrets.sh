#!/usr/bin/env bash
# Crée les secrets de DÉVELOPPEMENT dans le cluster, avec des valeurs aléatoires.
# Rien n'est écrit sur le disque ni dans git. (Remplacé par un vrai gestionnaire de secrets à l'étape 5.)
set -euo pipefail
NS=taskvault
kubectl apply -f "$(dirname "$0")/../k8s/base/namespace.yaml" >/dev/null
# Idempotent : ne régénère pas un secret existant (le mot de passe de la base est fixé au premier démarrage).
if kubectl -n "$NS" get secret taskvault-db taskvault-app >/dev/null 2>&1; then
  echo "Secrets déjà présents."; exit 0
fi
rnd() { head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32; }

kubectl -n "$NS" create secret generic taskvault-db \
  --from-literal=DB_USER=taskvault \
  --from-literal=DB_PASSWORD="$(rnd)" \
  --from-literal=DB_NAME=taskvault \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" create secret generic taskvault-app \
  --from-literal=JWT_SECRET="$(rnd)$(rnd)" \
  --dry-run=client -o yaml | kubectl apply -f -
