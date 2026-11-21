variable "cluster_name" {
  description = "Nom du cluster kind."
  type        = string
  default     = "taskvault"
}

variable "kubeconfig_path" {
  description = "Fichier kubeconfig dans lequel kind enregistre le contexte du cluster."
  type        = string
  default     = "~/.kube/config"
}

variable "worker_count" {
  description = "Nombre de nœuds workers."
  type        = number
  default     = 2
}
