#!/usr/bin/env bash
# Installe Falco (détection à l'exécution, driver eBPF "modern", règles propres à TaskVault).
# Prérequis : noyau avec BTF (/sys/kernel/btf/vmlinux présent), ce qui est le cas de WSL2 récent.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -e /sys/kernel/btf/vmlinux ] || { echo "BTF absent : le driver modern_ebpf de Falco ne fonctionnera pas." >&2; exit 1; }
helm repo add falcosecurity https://falcosecurity.github.io/charts >/dev/null 2>&1 || true
helm repo update falcosecurity >/dev/null
helm upgrade --install falco falcosecurity/falco --version 9.2.2 -n falco --create-namespace \
  -f k8s/falco/values.yaml --wait --timeout 8m
