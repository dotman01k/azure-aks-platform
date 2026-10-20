# Validation evidence

Created on 20 October 2026 UTC.

| Check | Result |
| --- | --- |
| Terraform 1.13.0 recursive formatting | Passed |
| AzureRM 4.52.0 signed provider installation and dependency lock | Passed |
| API unit tests | 4 passed: liveness, readiness, no secret disclosure, metrics and unknown route behavior |
| Dev and prod Kustomize rendering | Passed with kubectl 1.34.1 |
| Rendered manifest security and availability assertions | Passed for both overlays |
| Shell syntax | Passed for every shell script |
| GitHub Actions workflow syntax | Passed with actionlint 1.7.7 and declared custom runner label |
| Full Terraform provider schema validation | Passed on GitHub Actions; local provider IPC is restricted |
| Docker build | Passed on GitHub Actions; Docker is unavailable locally |
| Trivy image vulnerability scan | Passed on GitHub Actions: no fixable HIGH/CRITICAL findings blocked the build |
| Azure provisioning and workload identity integration | Not executed; requires configured Azure subscription, identities, state backend and connected runner |

The repository's AKS Validate workflow is the authoritative result for cloud-independent provider validation and container build/scan on a GitHub-hosted runner. Check its latest run before deploying. No Terraform apply, Azure resource creation or real secret upload occurred while creating this project.

GitHub validation run: https://github.com/dotman01k/azure-aks-platform/actions/runs/39374732177

The linked run passed in this dedicated repository after the workflow paths and documentation were updated for the standalone layout.
