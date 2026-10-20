# Setup and deployment

## Prerequisites

Use an Azure commercial subscription, Azure CLI, Terraform 1.13.0, Python 3.12, Docker, and GitHub Actions. Initial setup requires resource-provider registration rights, managed identity creation rights and role-assignment permissions. The bootstrap script assumes an interactive Azure user (`az login`) and is not a service principal bootstrap.

Check `az aks get-versions --location eastus -o table` and `az vm list-usage --location eastus -o table`. Confirm D2s_v5 capacity, available zones, and at least 4 vCPUs for the dev minimum or 12 for the prod minimum, plus surge and autoscaling headroom. A subscription with zero DSv5 quota must request quota or choose a supported system-pool size before deployment.

The platform uses fixed, isolated address spaces: VNet `10.20.0.0/16`, pod `10.244.0.0/16`, service `10.240.0.0/16`. Dev and prod create separate VNets with the same ranges. Do not peer them without first changing the module to use non-overlapping environment-specific CIDRs.

## 1. Bootstrap identities and state

Run only after reviewing the script. Use different platform resource groups and identities for dev and prod. The state account can be shared, using different state keys.

```bash
az login
export SUBSCRIPTION_ID='<subscription-id>'
export DEPLOY_ENV=dev
export STATE_ACCOUNT='<globally-unique-storage-name>'
export GITHUB_REPOSITORY=dotman01k/azure-aks-platform
export LOCATION=eastus
bash scripts/bootstrap.sh
```

The script registers required providers, creates resource groups, storage and two user-assigned identities. It gives infrastructure CI Contributor plus User Access Administrator on only the platform resource group and Blob Data Contributor on the state account. These are powerful infrastructure permissions: protect the matching GitHub environments. The application identity gets its specific Azure permissions later through Terraform.

Storage shared keys and anonymous blob access are disabled. The state endpoint remains public for GitHub-hosted infrastructure jobs, secured by Entra RBAC. Restricting state networking requires a connected runner and workflow changes. After creation, enable storage blob versioning and soft delete according to your recovery policy. Role propagation can delay the first container-creation or pipeline attempt; retry after checking the identity and scope.

CI federation trusts exactly these subjects (replace owner/repository if forked):

| Identity | GitHub environment subjects |
| --- | --- |
| Dev infrastructure | `repo:dotman01k/azure-aks-platform:environment:dev-plan` and `...:environment:dev` |
| Dev application | `repo:dotman01k/azure-aks-platform:environment:dev-app` |
| Prod infrastructure | `repo:dotman01k/azure-aks-platform:environment:prod-plan` and `...:environment:prod` |
| Prod application | `repo:dotman01k/azure-aks-platform:environment:prod-app` |

## 2. Configure GitHub environments

Create `dev-plan`, `dev`, `dev-app`, and later the corresponding `prod` environments. Restrict deployments to `main`. Configure required reviewers for `dev`, `prod` and application environments, particularly production; availability depends on your GitHub plan and repository visibility. The repository is public, so do not put credentials in variables, files or workflow artifacts.

The plan and apply environments must use the same infra client identity, subscription, tenant, state storage and Terraform JSON. Use the bootstrap output's **client ID** for login and **principal ID** for Terraform role assignments; these are different identifiers.

| Variable | Environments | Value |
| --- | --- | --- |
| `AZURE_SUBSCRIPTION_ID` | All | Subscription ID |
| `AZURE_TENANT_ID` | All | Entra tenant ID |
| `INFRA_CLIENT_ID` | `dev-plan`, `dev`, prod equivalents | Infrastructure CI client ID |
| `APP_CLIENT_ID` | `dev-app`, `prod-app` | Application CI client ID |
| `STATE_RESOURCE_GROUP` | Plan and apply | `rg-aks-state` |
| `STATE_STORAGE_ACCOUNT` | Plan and apply | State storage account name |
| `TFVARS_JSON` | Plan and apply | JSON equivalent of your environment tfvars example |
| `AZURE_RESOURCE_GROUP` | Apply and app | `rg-aks-dev` or `rg-aks-prod` |
| `AKS_CLUSTER_NAME` | Apply and app | From Terraform outputs |
| `KEY_VAULT_NAME` | Apply | From Terraform outputs |
| `WORKLOAD_CLIENT_ID` | Apply | From Terraform outputs |
| `ACR_NAME` | App | Registry name from Terraform outputs |

Start from `infra/environments/dev.tfvars.example`. For `TFVARS_JSON`, convert the HCL assignments into a JSON object with identical keys and real values. Example shape:

```json
{
  "subscription_id": "YOUR_SUBSCRIPTION_ID",
  "resource_group_name": "rg-aks-dev",
  "name": "dotunaks",
  "environment": "dev",
  "location": "eastus",
  "admin_group_object_ids": ["YOUR_ENTRA_ADMIN_GROUP_OBJECT_ID"],
  "infra_principal_id": "YOUR_INFRA_IDENTITY_PRINCIPAL_ID",
  "app_principal_id": "YOUR_APP_IDENTITY_PRINCIPAL_ID",
  "alert_email": "you@example.com",
  "private_cluster": false,
  "authorized_cidrs": ["YOUR_ADMIN_PUBLIC_IP/32", "YOUR_RUNNER_PUBLIC_IP/32"],
  "zones": [],
  "system_min": 1,
  "system_max": 2,
  "app_min": 1,
  "app_max": 3
}
```

Example placeholders must be replaced. For a runner in the generated subnet, use the NAT egress IP as an authorized API CIDR for dev. You can initially provision with your administrator CIDR, then add the Terraform `egress_ip` output and apply an updated plan before initializing Kubernetes. A separate external Linux runner works for dev only if its public CIDR is allowed and it can reach private Key Vault through VPN/peering and private DNS.

## 3. Provision infrastructure

In Actions, run **AKS Infrastructure** with `environment=dev`, `operation=plan`. Review the saved plan artifact and job output.

To apply, run with `operation=apply`. The plan job produces a new saved plan; review **that run's** `plan.txt` before approving the apply environment. The apply job downloads the plan from the same workflow run. If environment reviewers are not configured, no approval pause exists. Saved plans contain configuration and may be sensitive; artifact retention is one day. This example deliberately has no real application secrets in Terraform inputs or state.

Download the `aks-outputs-dev` artifact after apply and populate the output-based environment variables above. No kubeconfig or credentials are exported as artifacts.

## 4. Provide a trusted connected runner

Register a Linux x64 GitHub Actions runner with labels `self-hosted`, `linux`, `aks`. Place it in the generated runner subnet, or use a privately connected network with private DNS resolution for AKS, Key Vault, and prod ACR. Install Azure CLI, Python 3 with venv support, Docker, curl and tar; allow the runner user to run Docker and write `$HOME/.local/bin`. GitHub Actions actions may download additional tools, so allow their documented outbound endpoints.

This project provisions a subnet, **not a VM or runner registration token**. Keep runner credentials out of Terraform and GitHub source. Use an isolated, ideally ephemeral runner. Do not run untrusted public PR code on it. Deployment workflows use only manual dispatch on `main`; validation uses GitHub-hosted runners. Azure CLI caches, kubeconfig, Docker login and local images persist on a reused runner unless you clean the machine or recycle it.

## 5. Initialize and release

Run **AKS Initialize Platform** as the infrastructure identity. It creates the namespace, quotas, policies, service account and SecretProviderClass, and writes a non-sensitive demo secret through private Key Vault. Wait for role assignments and private DNS to propagate before rerunning failures.

Run **AKS Release Application**. It builds the image on the connected runner, scans fixable HIGH/CRITICAL findings, pushes to ACR, resolves the digest, authenticates with Entra and applies application manifests in `portfolio`. Namespace-level Azure RBAC Writer is deliberately insufficient to bootstrap platform resources outside that namespace.

The release workflow reports a failure if rollout is not healthy after five minutes. It does not automatically roll back. Use the runbook to inspect the failure and roll back to a known digest.
