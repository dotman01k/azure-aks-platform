#!/usr/bin/env bash
# One-time, operator-authenticated bootstrap. Inspect before running.
set -euo pipefail
: "${SUBSCRIPTION_ID:?}"
: "${DEPLOY_ENV:?dev or prod}"
: "${STATE_ACCOUNT:?Globally unique lowercase storage account name}"
: "${GITHUB_REPOSITORY:?owner/repository}"
LOCATION=${LOCATION:-eastus}
[[ "$DEPLOY_ENV" == dev || "$DEPLOY_ENV" == prod ]]
az account set --subscription "$SUBSCRIPTION_ID"
for provider in Microsoft.ContainerService Microsoft.ContainerRegistry Microsoft.KeyVault Microsoft.Network Microsoft.ManagedIdentity Microsoft.OperationalInsights Microsoft.Insights Microsoft.PolicyInsights Microsoft.Compute Microsoft.Storage Microsoft.OperationsManagement; do
  az provider register --namespace "$provider" --wait
done
platform_rg="rg-aks-$DEPLOY_ENV"
state_rg=rg-aks-state
az group create -n "$platform_rg" -l "$LOCATION" -o none
az group create -n "$state_rg" -l "$LOCATION" -o none
# Shared-key access is disabled; state uses Entra authentication and blob locking.
az storage account create -g "$state_rg" -n "$STATE_ACCOUNT" -l "$LOCATION" --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 --allow-blob-public-access false --allow-shared-key-access false -o none
state_id=$(az storage account show -g "$state_rg" -n "$STATE_ACCOUNT" --query id -o tsv)
operator_id=$(az ad signed-in-user show --query id -o tsv)
az role assignment create --assignee-object-id "$operator_id" --assignee-principal-type User --role 'Storage Blob Data Contributor' --scope "$state_id" -o none
# RBAC propagation can take minutes. Retry this command if authorization is delayed.
az storage container create --account-name "$STATE_ACCOUNT" --name tfstate --auth-mode login -o none
for kind in infra app; do
  identity="aks-$DEPLOY_ENV-$kind-ci"
  az identity create -g "$platform_rg" -n "$identity" -o none
  identity_id=$(az identity show -g "$platform_rg" -n "$identity" --query principalId -o tsv)
  client_id=$(az identity show -g "$platform_rg" -n "$identity" --query clientId -o tsv)
  if [[ "$kind" == infra ]]; then
    scope="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$platform_rg"
    for role in Contributor 'User Access Administrator'; do
      az role assignment create --assignee-object-id "$identity_id" --assignee-principal-type ServicePrincipal --role "$role" --scope "$scope" -o none
    done
    az role assignment create --assignee-object-id "$identity_id" --assignee-principal-type ServicePrincipal --role 'Storage Blob Data Contributor' --scope "$state_id" -o none
    environments=("$DEPLOY_ENV-plan" "$DEPLOY_ENV")
  else
    environments=("$DEPLOY_ENV-app")
  fi
  for environment in "${environments[@]}"; do
    az identity federated-credential create -g "$platform_rg" --identity-name "$identity" --name "github-$environment" --issuer https://token.actions.githubusercontent.com --subject "repo:$GITHUB_REPOSITORY:environment:$environment" --audiences api://AzureADTokenExchange -o none
  done
  printf '%s client ID: %s\n%s principal ID: %s\n' "$kind" "$client_id" "$kind" "$identity_id"
done
printf 'State storage account: %s\nPlatform resource group: %s\n' "$STATE_ACCOUNT" "$platform_rg"
