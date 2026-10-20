resource "azurerm_container_registry" "main" {
  name                          = "${var.name}${var.environment}${local.unique}acr"
  location                      = var.location
  resource_group_name           = data.azurerm_resource_group.platform.name
  sku                           = var.environment == "prod" ? "Premium" : "Basic"
  admin_enabled                 = false
  public_network_access_enabled = var.environment != "prod"
  tags                          = local.tags
}
resource "azurerm_key_vault" "main" {
  name                          = "${var.name}-${var.environment}-${local.unique}"
  location                      = var.location
  resource_group_name           = data.azurerm_resource_group.platform.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  public_network_access_enabled = false
  purge_protection_enabled      = true
  soft_delete_retention_days    = 7
  tags                          = local.tags
}
locals {
  private_services = merge({
    vault = { id = azurerm_key_vault.main.id, group = "vault", zone = "privatelink.vaultcore.azure.net" }
    }, var.environment == "prod" ? {
    registry = { id = azurerm_container_registry.main.id, group = "registry", zone = "privatelink.azurecr.io" }
  } : {})
}
resource "azurerm_private_dns_zone" "services" {
  for_each            = local.private_services
  name                = each.value.zone
  resource_group_name = data.azurerm_resource_group.platform.name
  tags                = local.tags
}
resource "azurerm_private_dns_zone_virtual_network_link" "services" {
  for_each              = local.private_services
  name                  = "${local.prefix}-${each.key}"
  resource_group_name   = data.azurerm_resource_group.platform.name
  private_dns_zone_name = azurerm_private_dns_zone.services[each.key].name
  virtual_network_id    = module.network.vnet_id
  registration_enabled  = false
}
resource "azurerm_private_endpoint" "services" {
  for_each            = local.private_services
  name                = "${local.prefix}-${each.key}-pe"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.platform.name
  subnet_id           = module.network.private_subnet_id
  private_service_connection {
    name                           = each.key
    private_connection_resource_id = each.value.id
    subresource_names              = [each.value.group]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.services[each.key].id]
  }
  tags = local.tags
}
resource "azurerm_user_assigned_identity" "workload" {
  name                = "${local.prefix}-workload"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.platform.name
  tags                = local.tags
}
resource "azurerm_federated_identity_credential" "workload" {
  name                = "portfolio-api"
  resource_group_name = data.azurerm_resource_group.platform.name
  parent_id           = azurerm_user_assigned_identity.workload.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject             = "system:serviceaccount:portfolio:portfolio-api"
}
resource "azurerm_role_assignment" "secret_reader" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
}
resource "azurerm_role_assignment" "image_pull" {
  scope                            = azurerm_container_registry.main.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}
resource "azurerm_role_assignment" "image_push" {
  scope                            = azurerm_container_registry.main.id
  role_definition_name             = "AcrPush"
  principal_id                     = var.app_principal_id
  skip_service_principal_aad_check = true
}
resource "azurerm_role_assignment" "app_user" {
  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = var.app_principal_id
}
resource "azurerm_role_assignment" "app_writer" {
  scope                = "${azurerm_kubernetes_cluster.main.id}/namespaces/portfolio"
  role_definition_name = "Azure Kubernetes Service RBAC Writer"
  principal_id         = var.app_principal_id
}
resource "azurerm_role_assignment" "infra_user" {
  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = var.infra_principal_id
}
resource "azurerm_role_assignment" "infra_admin" {
  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = var.infra_principal_id
}
resource "azurerm_role_assignment" "seed_secrets" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.infra_principal_id
}
