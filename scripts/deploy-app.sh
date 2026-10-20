#!/usr/bin/env bash
set -euo pipefail
: "${DEPLOY_ENV:?}"
: "${IMAGE_DIGEST:?Use an immutable ACR image digest}"
[[ "$DEPLOY_ENV" == dev || "$DEPLOY_ENV" == prod ]]
[[ "$IMAGE_DIGEST" =~ ^[a-z0-9]+\.azurecr\.io/portfolio-api@sha256:[a-f0-9]{64}$ ]]
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -R k8s/app "$work/app"
cat >> "$work/app/overlays/$DEPLOY_ENV/kustomization.yaml" <<EOF
images:
  - name: portfolio-api
    newName: ${IMAGE_DIGEST%@*}
    digest: ${IMAGE_DIGEST#*@}
EOF
# Preserve the HPA's current replica count on subsequent deployments.
kubectl kustomize "$work/app/overlays/$DEPLOY_ENV" | python3 scripts/omit-replicas.py | kubectl apply --server-side --field-manager=portfolio-release -f -
kubectl -n portfolio rollout status deployment/portfolio-api --timeout=300s
kubectl -n portfolio get deployment,pods,service,hpa,pdb
