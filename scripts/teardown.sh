#!/usr/bin/env bash
# Démontage propre, appelé par Terraform AVANT la désinstallation des releases Helm.
# Problème traité : Argo CD et External Secrets créent des ressources hors de Terraform (applications,
# ExternalSecret avec finalizers). Si on désinstalle External Secrets d'abord, plus aucun contrôleur ne peut
# les finaliser : la désinstallation expire et laisse les CRD bloquées en suppression.
# On les supprime donc ici, tant que les contrôleurs tournent encore. Best effort : ne fait jamais échouer le destroy.
set -uo pipefail
CLUSTER="${CLUSTER_NAME:-taskvault}"
kubectl config use-context "kind-$CLUSTER" >/dev/null 2>&1 || { echo "Cluster absent, rien à démonter."; exit 0; }

# 1. Argo CD ne doit plus recréer ce qu'on supprime (selfHeal).
kubectl -n argocd scale statefulset/argocd-application-controller --replicas=0 --timeout=60s 2>/dev/null
kubectl -n argocd delete applications.argoproj.io --all --wait=false --timeout=60s 2>/dev/null
# 2. Ressources External Secrets (finalizers gérés par le contrôleur, encore présent).
kubectl delete externalsecrets.external-secrets.io --all --all-namespaces --timeout=90s 2>/dev/null
kubectl delete clustersecretstores.external-secrets.io --all --timeout=60s 2>/dev/null
# 3. Le namespace applicatif (pods, PVC, politiques Kyverno).
kubectl delete namespace taskvault --ignore-not-found --timeout=120s 2>/dev/null
echo "Démontage terminé."
exit 0
