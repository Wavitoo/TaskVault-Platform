#!/usr/bin/env bash
# Teste le durcissement : chaque contrôle doit bloquer le mauvais cas ET laisser passer le bon.
# Un contrôle qui n'a jamais été vu bloquer quelque chose n'est pas une preuve.
set -uo pipefail
NS=taskvault
PASS=0; FAIL=0
ok()   { echo "  [OK]   $1"; PASS=$((PASS+1)); }
ko()   { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

SEC='"securityContext":{"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}}'
CSEC='"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}'

# run_pod <nom> <labels> <commande...> : lance un pod conforme et renvoie son code de sortie
run_pod() {
  local name=$1 labels=$2; shift 2
  kubectl -n $NS run "$name" --rm -i --restart=Never --quiet --labels="$labels" \
    --image=curlimages/curl:8.11.1 \
    --overrides="{\"spec\":{\"automountServiceAccountToken\":false,$SEC,\"containers\":[{\"name\":\"$name\",\"image\":\"curlimages/curl:8.11.1\",$CSEC,\"command\":[\"sh\",\"-c\",\"$*\"]}]}}" \
    >/dev/null 2>&1
}

echo "== Réseau (NetworkPolicy) =="
run_pod t-allowed "role=client" "curl -sf -m 5 http://backend/health" \
  && ok "un pod 'role=client' joint le backend" || ko "un pod 'role=client' devrait joindre le backend"
# Intrus dans un AUTRE namespace (sortie libre) : seul l'ingress du backend peut le bloquer.
kubectl create ns tv-intruder >/dev/null 2>&1 || true
kubectl -n tv-intruder run t-intruder --rm -i --restart=Never --quiet --image=curlimages/curl:8.11.1 \
  --command -- curl -sf -m 5 http://backend.taskvault.svc/health >/dev/null 2>&1 \
  && ko "un pod d'un autre namespace ne devrait PAS joindre le backend" || ok "un pod d'un autre namespace est bloqué vers le backend"
kubectl delete ns tv-intruder --wait=false >/dev/null 2>&1
run_pod t-db "role=client" "nc -z -w 3 postgres 5432" \
  && ko "un client ne devrait PAS joindre la base" || ok "un client ne peut pas joindre la base directement"

echo "== Application de bout en bout =="
U="u$RANDOM"
run_pod t-flow "role=client" "curl -sf -m 5 -X POST -H 'Content-Type: application/json' -d '{\\\"username\\\":\\\"$U\\\",\\\"password\\\":\\\"Pw-test-123\\\"}' http://backend/api/auth/register && curl -sf -m 5 -X POST -H 'Content-Type: application/json' -d '{\\\"username\\\":\\\"$U\\\",\\\"password\\\":\\\"Pw-test-123\\\"}' http://backend/api/auth/login" \
  && ok "inscription + connexion (backend -> base) fonctionnent" || ko "le flux inscription/connexion échoue"

echo "== Pod Security (restricted) =="
OUT=$(kubectl -n $NS run t-priv --restart=Never --image=busybox --privileged -- sleep 1 2>&1)
if grep -qi 'forbidden\|violates' <<<"$OUT"; then
  ok "un pod privilégié est refusé"
else ko "un pod privilégié aurait dû être refusé"; kubectl -n $NS delete pod t-priv --ignore-not-found >/dev/null 2>&1; fi
OUT=$(kubectl -n $NS run t-root --restart=Never --image=busybox -- sleep 1 2>&1)
if grep -qi 'forbidden\|violates' <<<"$OUT"; then
  ok "un pod sans durcissement (root possible) est refusé"
else ko "un pod non durci aurait dû être refusé"; kubectl -n $NS delete pod t-root --ignore-not-found >/dev/null 2>&1; fi

echo "== Chaîne d'approvisionnement (Kyverno) =="
kubectl -n $NS get pod -l app=backend -o jsonpath='{.items[*].spec.containers[0].image}' | tr ' ' '\n' | grep -v '^ghcr.io/wavitoo/taskvault-backend@sha256:' | grep -q . \
  && ko "un pod backend tourne avec une image non épinglée par digest GHCR" || ok "le backend tourne avec l'image GHCR épinglée par digest (signée)"
FOREIGN='{"spec":{"automountServiceAccountToken":false,'"$SEC"',"containers":[{"name":"x","image":"ghcr.io/sigstore/cosign/cosign:v2.4.1",'"$CSEC"'}]}}'
OUT=$(kubectl -n $NS run t-foreign --image=ghcr.io/sigstore/cosign/cosign:v2.4.1 --overrides="$FOREIGN" --dry-run=server 2>&1)
# On exige le motif précis (identité différente), pas n'importe quelle erreur : sinon le test pourrait passer pour la mauvaise raison.
if grep -q 'none of the expected identities matched' <<<"$OUT"; then
  ok "une image GHCR signée par un AUTRE signataire est refusée (identité non reconnue)"
else ko "image d'un autre signataire : refus pour la mauvaise raison ou acceptée"; echo "$OUT" | head -3; fi

echo "== Secrets (Vault + External Secrets) =="
ROOT=$(cd "$(dirname "$0")/.." && pwd)
grep -rqE '^kind: Secret$' "$ROOT/k8s" \
  && ko "un objet Secret (avec valeurs) est présent dans le dépôt" || ok "aucun objet Secret dans le dépôt : seules des références (ExternalSecret) sont versionnées"
kubectl -n $NS get secret taskvault-db taskvault-app -o jsonpath='{range .items[*]}{.metadata.ownerReferences[0].kind}{"\n"}{end}' | grep -vq ExternalSecret \
  && ko "un secret n'est pas géré par External Secrets" || ok "les secrets sont créés et possédés par External Secrets (source : Vault)"
kubectl -n $NS exec postgres-0 -- env 2>/dev/null | grep -q '^POSTGRES_PASSWORD=' \
  && ko "le mot de passe Postgres est visible en variable d'environnement" || ok "le mot de passe Postgres n'est pas en variable d'environnement (fichier monté)"
# Moindre privilège côté Vault : un jeton avec la politique d'ESO lit taskvault/* mais rien d'autre.
TOK=$(kubectl -n vault exec vault-0 -- env VAULT_TOKEN=root VAULT_ADDR=http://127.0.0.1:8200 vault token create -policy=taskvault-read -field=token 2>/dev/null)
cap() { kubectl -n vault exec vault-0 -- env VAULT_TOKEN=root VAULT_ADDR=http://127.0.0.1:8200 vault token capabilities "$TOK" "$1" 2>/dev/null; }
[ "$(cap secret/data/taskvault/db)" = "read" ] && ok "la politique ESO peut lire secret/taskvault/*" || ko "la politique ESO ne peut pas lire secret/taskvault/*"
[ "$(cap secret/data/autre/chose)" = "deny" ] && ok "la politique ESO ne peut PAS lire un autre chemin (moindre privilège)" || ko "la politique ESO est trop large"
cap secret/data/taskvault/db | grep -qE 'create|update|delete' \
  && ko "la politique ESO permet d'écrire" || ok "la politique ESO est en lecture seule (ni écriture ni suppression)"

echo "== GitOps (Argo CD) =="
BAD=$(kubectl -n argocd get applications.argoproj.io -o jsonpath='{range .items[*]}{.metadata.name}={.status.sync.status}/{.status.health.status}{"\n"}{end}' | grep -v '=Synced/Healthy$' || true)
[ -z "$BAD" ] && ok "toutes les applications Argo CD sont Synced et Healthy" || { ko "applications non synchronisées : $BAD"; }
# Dérive : une modification manuelle du cluster doit être annulée par Argo CD (selfHeal).
kubectl -n $NS scale deploy/backend --replicas=5 >/dev/null 2>&1
R=5; for _ in $(seq 1 30); do R=$(kubectl -n $NS get deploy backend -o jsonpath='{.spec.replicas}'); [ "$R" = "2" ] && break; sleep 3; done
[ "$R" = "2" ] && ok "une modification manuelle (5 réplicas) est annulée par Argo CD" || ko "la dérive manuelle n'a pas été corrigée (réplicas=$R)"
# Périmètre : une application du projet taskvault ne peut pas viser un autre namespace.
cat <<'APP' | kubectl apply -f - >/dev/null 2>&1
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: { name: t-escape, namespace: argocd }
spec:
  project: taskvault
  source: { repoURL: git@github.com:Wavitoo/taskvault-platform.git, targetRevision: main, path: k8s/base }
  destination: { server: https://kubernetes.default.svc, namespace: kube-system }
APP
sleep 10
MSG=$(kubectl -n argocd get application t-escape -o jsonpath='{.status.conditions[0].message}' 2>/dev/null)
kubectl -n argocd delete application t-escape >/dev/null 2>&1
grep -q 'do not match any of the allowed destinations' <<<"$MSG" \
  && ok "une application hors du namespace taskvault est refusée par le projet Argo CD" || ko "le projet Argo CD n'a pas bloqué la destination interdite"

echo "== Surface d'attaque =="
kubectl -n $NS get pod -l app=backend -o jsonpath='{.items[0].spec.containers[0].securityContext.readOnlyRootFilesystem}' | grep -q true \
  && ok "système de fichiers du backend en lecture seule" || ko "système de fichiers du backend modifiable"
kubectl -n $NS get svc -o jsonpath='{range .items[*]}{.spec.type}{"\n"}{end}' | grep -vq ClusterIP \
  && ko "un service est exposé hors du cluster" || ok "aucun service exposé hors du cluster (base incluse)"

echo; echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
