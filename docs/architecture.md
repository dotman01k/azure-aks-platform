# Design decisions and boundaries

## Separation of responsibility

Terraform manages Azure infrastructure. Kubernetes namespace, service-account identity binding and network policies are initialized by the infrastructure identity. Routine application releases use a distinct managed identity with AcrPush, AKS Cluster User, and AKS RBAC Writer scoped to `/namespaces/portfolio`. A human Entra admin group provides recovery access; local admin credentials are disabled.

CI login uses GitHub OIDC. Application access to Key Vault uses a different federation: AKS issuer, `system:serviceaccount:portfolio:portfolio-api` subject and the Azure token-exchange audience. The CSI provider mounts the secret without copying it into a Kubernetes Secret. Secret rotation is enabled and the Python app reads the mounted file's existence on each request. It never returns its contents.

## Network choices

CNI Overlay avoids allocating a VNet IP for every pod. Cilium enforces Kubernetes network policy. A default-deny policy isolates the portfolio namespace; explicit rules allow DNS, same-namespace client ingress and outbound TCP 443. The HTTPS rule allows any destination on port 443. It does not enforce a destination or FQDN allowlist. CSI provider traffic is issued by its own managed system components and is not fully governed by the application's NetworkPolicy.

AKS uses a user-managed NAT Gateway for predictable outbound IP. Public nodes, inbound SSH and public application services are not configured. Kubernetes nodes retain the Azure-required outbound dependencies through NAT. This is not a firewall-inspected network; a regulated production environment may require Azure Firewall, route tables, more detailed egress rules and a reviewed NSG design.

Key Vault has private access in both profiles. ACR Basic is public and RBAC-protected in dev. Production uses Premium ACR with private access and private DNS. The API server is public with explicit authorized ranges in dev and private with AKS-managed private DNS in prod. A runner inside the VNet or equivalent private connectivity is needed for deployment and secret seeding.

## Availability and resource ownership

The system pool is tainted for critical add-ons. Apps have a dedicated tainted pool with matching toleration and node selector. Production starts with three nodes per pool across three zones. The application uses HPA with CPU requests, rolling updates, maxUnavailable=0, startup/readiness/liveness probes, zone spread and a PDB that preserves at least two replicas when at the production minimum.

Terraform does not manage pod replicas. Release scripts strip `Deployment.spec.replicas` before applying so HPA owns that field. Human `kubectl apply -k` includes preview replica counts; use the release script for routine deployment. AKS owns autoscaled node counts because Terraform config sets only min/max.

Log Analytics collects container data and selected control-plane diagnostic categories. A CPU alert sends email through an action group. The sample `/metrics` endpoint is available for a future Prometheus collector; the project does **not** provision managed Prometheus or automatically configure custom scraping. Log caps are ingestion controls, not cost guarantees; alerts do not implement application SLO monitoring.

## Security and delivery tradeoffs

Infrastructure CI has RG-level RBAC delegation rights and cluster administrator rights for initialization. Protect it accordingly. Application namespace Writer is broader than a custom minimal Deployment-only role, and can manage other namespace resources. Further constrain it if namespace tenancy requires stronger isolation.

Action references and the base image use version tags with Dependabot rather than claiming immutable supply-chain pinning. Terraform is exactly pinned with a signed provider lock file. Kubernetes application releases are pinned by image digest. Before a production rollout, review and pin action commit SHAs and base-image digests according to your supply-chain process.

No public ingress, certificate automation, backup/restore operator, disaster recovery, Defender subscription plan, policy assignments or compliance attestation is included. Enabling the Azure Policy add-on does not itself enforce an organizational policy baseline. The app contains no persistent business data. All production adoption requires a security review and a deployment test in the target subscription.
