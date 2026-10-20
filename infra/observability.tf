resource "azurerm_log_analytics_workspace" "main" {
  name                = "${local.prefix}-logs"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.platform.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = var.environment == "prod" ? 5 : 1
  tags                = local.tags
}
resource "azurerm_monitor_diagnostic_setting" "controlplane" {
  name                           = "control-plane-audit"
  target_resource_id             = azurerm_kubernetes_cluster.main.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.main.id
  log_analytics_destination_type = "Dedicated"
  enabled_log { category = "kube-audit-admin" }
  enabled_log { category = "kube-apiserver" }
  enabled_log { category = "kube-controller-manager" }
  enabled_metric { category = "AllMetrics" }
}
resource "azurerm_monitor_action_group" "ops" {
  name                = "${local.prefix}-ops"
  resource_group_name = data.azurerm_resource_group.platform.name
  short_name          = "aksops"
  email_receiver {
    name                    = "operator"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
}
resource "azurerm_monitor_metric_alert" "cpu" {
  name                = "${local.prefix}-node-cpu"
  resource_group_name = data.azurerm_resource_group.platform.name
  scopes              = [azurerm_kubernetes_cluster.main.id]
  description         = "Average node CPU exceeded 85 percent for 15 minutes."
  frequency           = "PT5M"
  window_size         = "PT15M"
  severity            = 2
  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "node_cpu_usage_percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 85
  }
  action { action_group_id = azurerm_monitor_action_group.ops.id }
}
