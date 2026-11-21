#!/usr/bin/env bash
# Configure Vault (mode dev) : secrets aléatoires, authentification Kubernetes, politique en lecture seule.
# Idempotent : ne régénère jamais un secret déjà présent (le mot de passe de la base est fixé au 1er démarrage).
# Les valeurs ne sont ni affichées ni écrites sur disque.
set -euo pipefail
V() { kubectl -n vault exec -i vault-0 -- env VAULT_TOKEN=root VAULT_ADDR=http://127.0.0.1:8200 vault "$@"; }
rnd() { head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32; }

# 1. Secrets (KV v2 monté sur secret/ en mode dev)
if V kv get -field=DB_PASSWORD secret/taskvault/db >/dev/null 2>&1; then
  echo "Secrets déjà présents dans Vault."
else
  V kv put secret/taskvault/db DB_USER=taskvault DB_NAME=taskvault DB_PASSWORD="$(rnd)" >/dev/null
  V kv put secret/taskvault/app JWT_SECRET="$(rnd)$(rnd)" >/dev/null
  echo "Secrets créés dans Vault."
fi

# 2. Politique : lecture seule sur secret/taskvault/*, rien d'autre
V policy write taskvault-read - >/dev/null <<'POLICY'
path "secret/data/taskvault/*" {
  capabilities = ["read"]
}
POLICY

# 3. Auth Kubernetes : ESO prouve son identité avec le jeton de son ServiceAccount (aucun token statique)
V auth list -format=json | grep -q '"kubernetes/"' || V auth enable kubernetes >/dev/null
V write auth/kubernetes/config kubernetes_host="https://kubernetes.default.svc" >/dev/null
V write auth/kubernetes/role/eso \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=taskvault-read ttl=15m >/dev/null
echo "Vault configuré (auth Kubernetes + politique taskvault-read)."
