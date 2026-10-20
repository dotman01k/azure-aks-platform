#!/usr/bin/env bash
set -euo pipefail
: "${KEY_VAULT_NAME:?}"
: "${WORKLOAD_CLIENT_ID:?}"
: "${AZURE_TENANT_ID:?}"
cd "$(dirname "$0")/.."
# This deliberately creates ONLY a non-sensitive demonstration secret.
# Real application secrets should be supplied through your approved secret process.
az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name demo-message --value "AKS workload identity is working" --output none
kubectl apply -f k8s/platform/namespace.yaml
kubectl apply -f k8s/platform/network.yaml
python3 - <<'RENDER' | kubectl apply -f -
import os
from pathlib import Path
from string import Template
print(Template(Path('k8s/platform/identity.yaml.template').read_text()).substitute(os.environ))
RENDER
