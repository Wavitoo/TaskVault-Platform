#!/usr/bin/env bash
# Construit l'image TaskVault depuis son dépôt (en lecture seule) et la charge dans kind.
# Usage : TASKVAULT_SRC=/chemin/vers/devsecops-security-pipeline ./scripts/build-load-image.sh
set -euo pipefail
SRC="${TASKVAULT_SRC:-$HOME/devsecops-security-pipeline}"
docker build -t taskvault-backend:local "$SRC/backend"
kind load docker-image taskvault-backend:local --name taskvault
