# Interview walkthrough

Describe this honestly as a portfolio implementation until you have deployed and tested it.

“I built an AKS platform using Terraform and GitHub Actions. It separates system and application node pools, uses Entra RBAC instead of local admin credentials, and connects application service accounts to managed identities using OIDC. The production profile has a private API and private service endpoints. Application releases scan images, deploy immutable digests and wait for health checks.”

## Be ready to explain

1. Why CI federation and Kubernetes workload federation have different issuers and subjects.
2. Why the kubelet needs AcrPull while the build identity needs AcrPush.
3. How the platform runner reaches private AKS, Key Vault and ACR.
4. How HPA and cluster autoscaler solve different capacity problems.
5. Why three replicas on one dev node do not provide host-level availability.
6. How readiness, liveness and startup probes affect a release.
7. Why PDBs govern voluntary disruption but do not guarantee protection against every outage.
8. How namespace Writer differs from cluster administrator.
9. What the egress policy permits and why it is not a complete outbound firewall.
10. What is still needed before production: deployment evidence, ingress/TLS if required, backup/restore, alerting SLOs, supply-chain pinning, maintenance windows and security review.

After deployment, retain sanitized workflow results and screenshots of node distribution, health probes, scaling and rollback. Record actual results and failures; do not claim tests that have not run.
