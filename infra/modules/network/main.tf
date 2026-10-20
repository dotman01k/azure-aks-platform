variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "tags" { type = map(string) }
resource "azurerm_virtual_network" "main" {
  name                = "${var.name}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = ["10.20.0.0/16"]
  tags                = var.tags
}
resource "azurerm_subnet" "nodes" {
  name                 = "aks-nodes"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.20.0.0/22"]
}
resource "azurerm_subnet" "private" {
  name                 = "private-endpoints"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.20.4.0/24"]
}
resource "azurerm_subnet" "runners" {
  name                 = "runners"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.20.5.0/24"]
}
resource "azurerm_public_ip" "egress" {
  name                = "${var.name}-egress"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}
resource "azurerm_nat_gateway" "main" {
  name                = "${var.name}-nat"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "Standard"
  tags                = var.tags
}
resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.egress.id
}
resource "azurerm_subnet_nat_gateway_association" "nodes" {
  subnet_id      = azurerm_subnet.nodes.id
  nat_gateway_id = azurerm_nat_gateway.main.id
  depends_on     = [azurerm_nat_gateway_public_ip_association.main]
}
resource "azurerm_subnet_nat_gateway_association" "runners" {
  subnet_id      = azurerm_subnet.runners.id
  nat_gateway_id = azurerm_nat_gateway.main.id
}
output "vnet_id" { value = azurerm_virtual_network.main.id }
output "nodes_subnet_id" {
  value      = azurerm_subnet.nodes.id
  depends_on = [azurerm_subnet_nat_gateway_association.nodes]
}
output "private_subnet_id" { value = azurerm_subnet.private.id }
output "runner_subnet_id" { value = azurerm_subnet.runners.id }
output "egress_ip" { value = azurerm_public_ip.egress.ip_address }
