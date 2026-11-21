# Cluster local gratuit : 1 control-plane + N workers, dans des conteneurs Docker.
resource "kind_cluster" "this" {
  name            = var.cluster_name
  kubeconfig_path = pathexpand(var.kubeconfig_path)
  wait_for_ready  = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"
    }

    dynamic "node" {
      for_each = range(var.worker_count)
      content {
        role = "worker"
      }
    }
  }
}

locals {
  values = "${path.module}/../k8s"
}

# Les versions de charts sont épinglées. Les valeurs vivent dans k8s/*/values.yaml (une seule source).

resource "helm_release" "vault" {
  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  version          = "0.34.1"
  namespace        = "vault"
  create_namespace = true
  values           = [file("${local.values}/vault/values.yaml")]
  wait             = true
  timeout          = 300
  depends_on       = [kind_cluster.this]
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "2.15.0"
  namespace        = "external-secrets"
  create_namespace = true
  values           = [file("${local.values}/external-secrets/values.yaml")]
  wait             = true
  timeout          = 300
  depends_on       = [kind_cluster.this]
}

resource "helm_release" "kyverno" {
  name             = "kyverno"
  repository       = "https://kyverno.github.io/kyverno"
  chart            = "kyverno"
  version          = "3.10.0"
  namespace        = "kyverno"
  create_namespace = true
  values           = [file("${local.values}/kyverno/values.yaml")]
  wait             = true
  timeout          = 300
  depends_on       = [kind_cluster.this]
}

resource "helm_release" "falco" {
  name             = "falco"
  repository       = "https://falcosecurity.github.io/charts"
  chart            = "falco"
  version          = "9.2.2"
  namespace        = "falco"
  create_namespace = true
  values           = [file("${local.values}/falco/values.yaml")]
  wait             = true
  timeout          = 480
  depends_on       = [kind_cluster.this]
}

# Argo CD arrive après Kyverno et ESO : les applications qu'il déploie utilisent leurs CRD.
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "10.18.2"
  namespace        = "argocd"
  create_namespace = true
  values           = [file("${local.values}/argocd/values.yaml")]
  wait             = true
  timeout          = 480
  depends_on       = [helm_release.kyverno, helm_release.external_secrets]
}

# Dernière étape : ce que Terraform ne sait pas faire proprement (configurer Vault, créer la clé de
# déploiement en lecture seule sur GitHub, poser l'application racine Argo CD).
resource "terraform_data" "bootstrap" {
  triggers_replace = [kind_cluster.this.id]
  input            = var.cluster_name

  provisioner "local-exec" {
    command     = "${path.module}/../scripts/bootstrap.sh"
    environment = { CLUSTER_NAME = var.cluster_name }
  }

  # Détruit AVANT les releases Helm (il en dépend) : supprime les ressources créées hors Terraform
  # tant que leurs contrôleurs existent encore. Sans cela, `terraform destroy` expire sur External Secrets.
  provisioner "local-exec" {
    when        = destroy
    command     = "${path.module}/../scripts/teardown.sh"
    environment = { CLUSTER_NAME = self.input }
    on_failure  = continue
  }

  depends_on = [helm_release.vault, helm_release.argocd, helm_release.falco]
}
