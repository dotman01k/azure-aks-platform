# Operations runbook

## Healthy rollout

Authenticate with Azure CLI as an authorized user, set `AZURE_RESOURCE_GROUP` and `AKS_CLUSTER_NAME`, then source `scripts/cluster-login.sh`. Private environments require VNet access and private DNS.

```bash
kubectl get nodes -L agentpool,topology.kubernetes.io/zone
kubectl -n portfolio get deploy,pods,hpa,pdb
kubectl -n portfolio rollout status deployment/portfolio-api --timeout=300s
kubectl -n portfolio get events --sort-by=.lastTimestamp
kubectl -n portfolio port-forward service/portfolio-api 8080:80
# In another terminal:
curl http://127.0.0.1:8080/
curl http://127.0.0.1:8080/readyz
curl http://127.0.0.1:8080/metrics
```

The root response should report `secret_mounted: true`; the secret value must never appear. The service has no internet endpoint. A pod client in the same namespace must carry label `access=portfolio-api` for network ingress.

## Failed CSI mount or workload identity

Inspect `kubectl -n portfolio describe pod <pod>` and `kubectl -n portfolio get secretproviderclass`. Verify the service-account client ID annotation, pod workload-identity label, managed identity issuer/audience/subject and Key Vault Secrets User scope. Verify the `demo-message` secret exists. From the connected runner, Key Vault DNS should resolve privately. Allow for RBAC and federation propagation, then retry. Do not disable Key Vault networking or paste tokens into issue logs to troubleshoot.

## ImagePullBackOff or authorization failure

Check exact digest and ACR repository, kubelet AcrPull assignment, registry DNS and private endpoint state. Application AcrPush does not grant kubelet image pull access; they are separate identities. For Kubernetes 403, verify the application identity has both AKS Cluster User and namespace-scoped AKS RBAC Writer. Platform initialization needs the infrastructure identity's administrator role.

## Scaling and upgrade drills

Use a temporary load generator with the allowed client label in `portfolio`, within quota. Observe `kubectl -n portfolio get hpa -w` and node pool autoscaling. Remove the generator afterward. HPA requires metrics-server data and CPU requests; allow several metrics intervals. Dev has one app node initially, so multiple pods do not imply host redundancy. Production enforces zone spread.

For maintenance, check spare quota and surge capacity, PDB status and supported Kubernetes versions before approving Terraform changes. Patch auto-upgrades and NodeImage OS upgrades are enabled. A maintenance window is not defined in this starter. Decide and configure one before adopting production workloads.

## Rollback

A failed release is reported, not automatically hidden by rollback. Inspect events, logs, image access and secret mount before choosing a rollback.

```bash
kubectl -n portfolio rollout history deployment/portfolio-api
kubectl -n portfolio rollout undo deployment/portfolio-api
kubectl -n portfolio rollout status deployment/portfolio-api --timeout=300s
```

For a repeatable release, set `DEPLOY_ENV` and `IMAGE_DIGEST` to a previous known-good ACR digest and run `scripts/deploy-app.sh` from the connected runner. A future release should use a reviewed commit, not an ad hoc cluster edit. Retain known-good registry images for rollback; no retention deletion task is configured.

## Log Analytics examples

```kusto
ContainerLogV2
| where TimeGenerated > ago(1h)
| where PodNamespace == "portfolio"
| project TimeGenerated, PodName, LogMessage
| order by TimeGenerated desc
```

```kusto
KubePodInventory
| where TimeGenerated > ago(1h) and Namespace == "portfolio"
| summarize arg_max(TimeGenerated, *) by Name, ClusterName
| project Name, PodStatus, ContainerRestartCount, Computer
```

## Cleanup

Destroy is intentionally absent from GitHub workflows. Review the target subscription, state key, resource list and backups first. For an explicitly disposable lab, initialize the correct backend with Azure CLI authentication (`use_oidc=false` locally) and review `terraform plan -destroy` before any destroy command. Existing projects in other state keys must never be targeted.

Terraform destroy removes only resources in this project's state. It retains bootstrap RGs, CI identities, federation, storage and the state container. Delete those separately only after verifying that no other environment depends on them. Purge-protected Key Vault remains recoverable for seven days and cannot be immediately recreated with the same name. AKS stop/start alone does not eliminate NAT, storage or other service charges.
