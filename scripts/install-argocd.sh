#!/usr/bin/env bash
# Installe Argo CD, lui donne un accès EN LECTURE SEULE au dépôt (clé de déploiement stockée dans Vault,
# livrée par External Secrets), puis démarre le GitOps.
# Prérequis : ./scripts/install-secrets.sh déjà exécuté (Vault + ESO).
# REVISION=ma-branche ./scripts/install-argocd.sh  -> teste une branche avant fusion (sans l'application racine).
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=Wavitoo/taskvault-platform
REVISION="${REVISION:-main}"
V() { kubectl -n vault exec -i vault-0 -- env VAULT_TOKEN=root VAULT_ADDR=http://127.0.0.1:8200 vault "$@"; }

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null
helm upgrade --install argocd argo/argo-cd --version 10.18.2 -n argocd --create-namespace \
  -f k8s/argocd/values.yaml --wait --timeout 8m

# Clé de déploiement : générée une seule fois, jamais écrite durablement sur disque, jamais dans git.
if V kv get -field=sshPrivateKey secret/argocd/repo >/dev/null 2>&1; then
  echo "Clé de déploiement déjà présente dans Vault."
else
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  ssh-keygen -q -t ed25519 -N '' -C argocd-readonly -f "$tmp/key"
  python3 -c 'import json,sys;print(json.dumps({"sshPrivateKey":open(sys.argv[1]).read()}))' "$tmp/key" | V kv put secret/argocd/repo - >/dev/null
  gh repo deploy-key add "$tmp/key.pub" --repo "$REPO" --title "argocd-readonly"   # lecture seule par défaut
  echo "Clé de déploiement créée (lecture seule) et stockée dans Vault."
fi

./scripts/configure-vault.sh >/dev/null   # s'assure que la politique ESO couvre secret/argocd/*
kubectl apply -f k8s/bootstrap/argocd-repo-externalsecret.yaml
kubectl -n argocd wait --for=condition=Ready externalsecret/repo-taskvault-platform --timeout=120s

if [ "$REVISION" = "main" ]; then
  kubectl apply -f argocd/root.yaml
else
  echo "Test de la branche $REVISION : applications appliquées directement."
  for f in argocd/apps/*.yaml; do sed "s#targetRevision: main#targetRevision: $REVISION#" "$f" | kubectl apply -f -; done
fi
