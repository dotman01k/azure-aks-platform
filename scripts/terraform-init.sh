#!/usr/bin/env bash
# Called with infra as working directory. No interpolation into shell commands.
set -euo pipefail
: "${TFVARS_JSON:?Set environment variable TFVARS_JSON to your configuration JSON}"
: "${STATE_RG:?}"
: "${STATE_ACCOUNT:?}"
: "${DEPLOY_ENV:?}"
python3 - <<'CHECK'
import json, os
from pathlib import Path
config = json.loads(os.environ['TFVARS_JSON'])
if config.get('environment') != os.environ['DEPLOY_ENV']:
    raise SystemExit('TFVARS_JSON environment does not match selected environment')
if config.get('subscription_id') != os.environ['ARM_SUBSCRIPTION_ID']:
    raise SystemExit('Subscription does not match Azure login')
Path('terraform.tfvars.json').write_text(json.dumps(config))
CHECK
terraform init -input=false -lockfile=readonly \
  -backend-config="resource_group_name=$STATE_RG" \
  -backend-config="storage_account_name=$STATE_ACCOUNT" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=advanced-aks-$DEPLOY_ENV.tfstate" \
  -backend-config="use_azuread_auth=true" \
  -backend-config="use_oidc=true"
