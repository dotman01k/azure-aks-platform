variable "subscription_id" { type = string }
variable "resource_group_name" { type = string }
variable "name" {
  type = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,9}$", var.name))
    error_message = "Use 3 to 10 lowercase letters and numbers, beginning with a letter."
  }
}
variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Choose dev or prod."
  }
}
variable "location" { type = string }
variable "kubernetes_version" {
  type        = string
  default     = null
  description = "Supported AKS minor or patch; null uses the regional recommended version."
}
variable "admin_group_object_ids" {
  type = list(string)
  validation {
    condition     = length(var.admin_group_object_ids) > 0
    error_message = "Supply at least one Entra administrator group object ID."
  }
}
variable "infra_principal_id" { type = string }
variable "app_principal_id" { type = string }
variable "private_cluster" { type = bool }
variable "authorized_cidrs" {
  type    = list(string)
  default = []
  validation {
    condition     = alltrue([for c in var.authorized_cidrs : can(cidrhost(c, 0)) && c != "0.0.0.0/0"])
    error_message = "Use explicit CIDRs, never 0.0.0.0/0."
  }
}
variable "zones" { type = list(string) }
variable "system_min" { type = number }
variable "system_max" { type = number }
variable "app_min" { type = number }
variable "app_max" { type = number }
variable "vm_size" {
  type    = string
  default = "Standard_D2s_v5"
}
variable "alert_email" { type = string }
variable "tags" {
  type    = map(string)
  default = { project = "advanced-aks", managed_by = "terraform" }
}
