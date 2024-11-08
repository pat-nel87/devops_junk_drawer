variable "vm_name" {
  description = "Name of the VM"
  type        = string
}

variable "resource_group_name" {
  description = "Resource Group name where the VM will be created"
  type        = string
}

variable "vnet_name" {
  description = "Name of the existing VNet to join"
  type        = string
}

variable "subnet_name" {
  description = "Name of the existing subnet in the VNet"
  type        = string
}

variable "location" {
  description = "Location of the resources"
  type        = string
  default     = "East US"
}
