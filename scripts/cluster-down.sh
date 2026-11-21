#!/usr/bin/env bash
# Supprime le cluster local "taskvault".
set -euo pipefail
kind delete cluster --name taskvault
