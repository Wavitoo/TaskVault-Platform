#!/usr/bin/env bash
# Amorçage après Terraform : Vault, accès d'Argo CD au dépôt (clé de déploiement lecture seule), application racine.
# Appelé par Terraform (terraform_data.bootstrap), idempotent, utilisable à la main.
# Prérequis : gh authentifié (création de la clé de déploiement).
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=Wavitoo/taskvault-platform
CLUSTER="${CLUSTER_NAME:-taskvault}"
kind export kubeconfig --name "$CLUSTER" >/dev/null 2>&1 || true
kubectl config use-context "kind-$CLUSTER" >/dev/null
V() { kubectl -n vault exec -i vault-0 -- env VAULT_TOKEN=root VAULT_ADDR=http://127.0.0.1:8200 vault "$@"; }

kubectl -n vault wait --for=condition=Ready pod/vault-0 --timeout=180s
# Les CRD d'External Secrets doivent être servies avant d'appliquer des ExternalSecret.
kubectl wait --for=condition=Established --timeout=180s \
  crd/externalsecrets.external-secrets.io crd/clustersecretstores.external-secrets.io
kubectl -n external-secrets rollout status deploy/external-secrets-webhook --timeout=180s
kubectl apply -f k8s/namespace/namespace.yaml
./scripts/configure-vault.sh

# ClusterSecretStore + ExternalSecret appliqués directement : Argo CD a besoin de ses identifiants pour lire
# le dépôt, et ceux-ci passent par ESO (poule et œuf). Argo CD adopte ensuite ces ressources.
kubectl apply -k k8s/secrets
kubectl -n taskvault wait --for=condition=Ready externalsecret/taskvault-db externalsecret/taskvault-app --timeout=180s

# Clé de déploiement : générée une seule fois par Vault, jamais écrite durablement sur disque, jamais dans git.
if V kv get -field=sshPrivateKey secret/argocd/repo >/dev/null 2>&1; then
  echo "Clé de déploiement déjà présente dans Vault."
else
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  ssh-keygen -q -t ed25519 -N '' -C argocd-readonly -f "$tmp/key"
  # Vault est en mémoire : un cluster recréé génère une nouvelle clé. On retire les anciennes pour ne pas les accumuler.
  for id in $(gh api "repos/$REPO/keys" --jq '.[] | select(.title=="argocd-readonly") | .id'); do
    gh api -X DELETE "repos/$REPO/keys/$id" >/dev/null
  done
  python3 -c 'import json,sys;print(json.dumps({"sshPrivateKey":open(sys.argv[1]).read()}))' "$tmp/key" | V kv put secret/argocd/repo - >/dev/null
  gh repo deploy-key add "$tmp/key.pub" --repo "$REPO" --title "argocd-readonly"   # lecture seule par défaut
  echo "Clé de déploiement créée (lecture seule) et stockée dans Vault."
fi

kubectl apply -f k8s/bootstrap/argocd-repo-externalsecret.yaml
kubectl -n argocd wait --for=condition=Ready externalsecret/repo-taskvault-platform --timeout=180s
kubectl apply -f argocd/root.yaml
echo "Amorçage terminé : Argo CD déploie TaskVault depuis Git."
