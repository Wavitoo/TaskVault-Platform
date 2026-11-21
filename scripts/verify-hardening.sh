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

echo "== Surface d'attaque =="
kubectl -n $NS get pod -l app=backend -o jsonpath='{.items[0].spec.containers[0].securityContext.readOnlyRootFilesystem}' | grep -q true \
  && ok "système de fichiers du backend en lecture seule" || ko "système de fichiers du backend modifiable"
kubectl -n $NS get svc -o jsonpath='{range .items[*]}{.spec.type}{"\n"}{end}' | grep -vq ClusterIP \
  && ko "un service est exposé hors du cluster" || ok "aucun service exposé hors du cluster (base incluse)"

echo; echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
