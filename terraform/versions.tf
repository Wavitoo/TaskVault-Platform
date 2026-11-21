terraform {
  required_version = ">= 1.9"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "0.13.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.3.0"
    }
  }
}

provider "helm" {
  kubernetes = {
    config_path    = var.kubeconfig_path
    config_context = "kind-${var.cluster_name}"
  }
}
