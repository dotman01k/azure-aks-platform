data "azurerm_client_config" "current" {}
data "azurerm_resource_group" "platform" { name = var.resource_group_name }
locals {
  prefix = "${var.name}-${var.environment}"
  unique = substr(sha256("${var.subscription_id}/${var.resource_group_name}/${var.name}"), 0, 8)
  tags   = merge(var.tags, { environment = var.environment })
}
module "network" {
  source              = "./modules/network"
  name                = local.prefix
  location            = var.location
  resource_group_name = data.azurerm_resource_group.platform.name
  tags                = local.tags
}
resource "azurerm_user_assigned_identity" "cluster" {
  name                = "${local.prefix}-controlplane"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.platform.name
  tags                = local.tags
}
resource "azurerm_role_assignment" "network" {
  scope                = module.network.vnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.cluster.principal_id
}
resource "azurerm_kubernetes_cluster" "main" {
  name                              = "${local.prefix}-aks"
  location                          = var.location
  resource_group_name               = data.azurerm_resource_group.platform.name
  dns_prefix                        = local.prefix
  kubernetes_version                = var.kubernetes_version
  sku_tier                          = var.environment == "prod" ? "Standard" : "Free"
  private_cluster_enabled           = var.private_cluster
  local_account_disabled            = true
  role_based_access_control_enabled = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
  azure_policy_enabled              = true
  automatic_upgrade_channel         = "patch"
  node_os_upgrade_channel           = "NodeImage"
  image_cleaner_enabled             = true
  image_cleaner_interval_hours      = 48
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster.id]
  }
  azure_active_directory_role_based_access_control {
    tenant_id              = data.azurerm_client_config.current.tenant_id
    admin_group_object_ids = var.admin_group_object_ids
    azure_rbac_enabled     = true
  }
  dynamic "api_server_access_profile" {
    for_each = var.private_cluster ? [] : [1]
    content { authorized_ip_ranges = var.authorized_cidrs }
  }
  default_node_pool {
    name                         = "system"
    vm_size                      = var.vm_size
    vnet_subnet_id               = module.network.nodes_subnet_id
    zones                        = var.zones
    auto_scaling_enabled         = true
    min_count                    = var.system_min
    max_count                    = var.system_max
    only_critical_addons_enabled = true
    temporary_name_for_rotation  = "sysrotate"
    os_disk_size_gb              = 64
    max_pods                     = 50
    upgrade_settings { max_surge = "33%" }
  }
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    pod_cidr            = "10.244.0.0/16"
    service_cidr        = "10.240.0.0/16"
    dns_service_ip      = "10.240.0.10"
    load_balancer_sku   = "standard"
    outbound_type       = "userAssignedNATGateway"
  }
  key_vault_secrets_provider { secret_rotation_enabled = true }
  oms_agent {
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.main.id
    msi_auth_for_monitoring_enabled = true
  }
  tags       = local.tags
  depends_on = [azurerm_role_assignment.network]
  lifecycle {
    precondition {
      condition     = var.private_cluster || length(var.authorized_cidrs) > 0
      error_message = "A public API requires explicit administrator and runner egress CIDRs."
    }
    precondition {
      condition     = var.environment != "prod" || (var.private_cluster && length(var.zones) == 3 && var.system_min >= 3 && var.app_min >= 3)
      error_message = "Production requires private API, three zones, and at least three nodes per pool."
    }
    precondition {
      condition     = var.system_max >= var.system_min && var.app_max >= var.app_min
      error_message = "Pool maximums must be at least their minimums."
    }
  }
}
resource "azurerm_kubernetes_cluster_node_pool" "apps" {
  name                  = "apps"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.vm_size
  vnet_subnet_id        = module.network.nodes_subnet_id
  zones                 = var.zones
  mode                  = "User"
  auto_scaling_enabled  = true
  min_count             = var.app_min
  max_count             = var.app_max
  os_disk_size_gb       = 64
  max_pods              = 50
  node_labels           = { workload = "apps" }
  node_taints           = ["workload=apps:NoSchedule"]
  upgrade_settings { max_surge = "33%" }
  tags = local.tags
}
