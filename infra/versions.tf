terraform {
  required_version = "~> 1.13.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 4.52.0"
    }
  }
  backend "azurerm" {}
}
provider "azurerm" {
  features {}
  subscription_id                 = var.subscription_id
  resource_provider_registrations = "none"
}
