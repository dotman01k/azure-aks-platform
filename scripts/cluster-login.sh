#!/usr/bin/env bash
set -euo pipefail
: "${AZURE_RESOURCE_GROUP:?Set AZURE_RESOURCE_GROUP}"
: "${AKS_CLUSTER_NAME:?Set AKS_CLUSTER_NAME}"
mkdir -p "$HOME/.local/bin"
# Match kubectl to the cluster; local admin accounts are deliberately disabled.
version=$(az aks show -g "$AZURE_RESOURCE_GROUP" -n "$AKS_CLUSTER_NAME" --query currentKubernetesVersion -o tsv)
az aks install-cli --client-version "v${version}" --install-location "$HOME/.local/bin/kubectl" --kubelogin-install-location "$HOME/.local/bin/kubelogin"
export PATH="$HOME/.local/bin:$PATH"
az aks get-credentials -g "$AZURE_RESOURCE_GROUP" -n "$AKS_CLUSTER_NAME" --overwrite-existing
kubelogin convert-kubeconfig -l azurecli
