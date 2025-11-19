# ==============================================================================
# Spoke Network Variables
# ==============================================================================
# This spoke module connects to a hub network with Azure Firewall
# and optionally a VPN Gateway. It creates VNet peering and routes
# all internet traffic through the hub's Azure Firewall.
# ==============================================================================

# ==============================================================================
# Basic Configuration
# ==============================================================================

variable "location" {
  description = "Azure region where spoke resources will be deployed (should match hub region)"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the resource group for spoke networking resources"
  type        = string
  default     = "rg-spoke-networking"
}

variable "create_resource_group" {
  description = "Whether to create a new resource group or use existing"
  type        = bool
  default     = true
}

# ==============================================================================
# Spoke VNet Configuration
# ==============================================================================

variable "spoke_vnet_name" {
  description = "Name of the spoke virtual network"
  type        = string
  default     = "vnet-spoke1"
}

variable "spoke_vnet_address_space" {
  description = "Address space for the spoke VNet (must not overlap with hub or other spokes)"
  type        = list(string)
  default     = ["10.1.0.0/16"]
}

variable "spoke_subnets" {
  description = "Map of subnets to create in the spoke VNet"
  type = map(object({
    address_prefix = string
    # Subnets where route table should be associated (for internet-bound traffic via firewall)
    associate_route_table = bool
  }))
  default = {
    "workload" = {
      address_prefix        = "10.1.0.0/24"
      associate_route_table = true
    }
  }
}

# ==============================================================================
# Hub Integration Variables
# ==============================================================================
# These values come from the hub module outputs
# Get them via: terraform output -state=../hub/terraform.tfstate spoke_integration_info
# ==============================================================================

variable "hub_vnet_id" {
  description = "Resource ID of the hub VNet (from hub module output)"
  type        = string
}

variable "hub_vnet_name" {
  description = "Name of the hub VNet (from hub module output)"
  type        = string
}

variable "hub_resource_group_name" {
  description = "Resource group name of the hub VNet (from hub module output)"
  type        = string
}

variable "firewall_private_ip" {
  description = "Private IP address of Azure Firewall in hub (from hub module output)"
  type        = string
}

# ==============================================================================
# VPN Gateway Integration
# ==============================================================================
# CRITICAL: If hub has VPN Gateway, these MUST be configured correctly
# ==============================================================================

variable "hub_has_vpn_gateway" {
  description = "Whether the hub has a VPN Gateway deployed (from hub module output)"
  type        = bool
  default     = false
}

# ==============================================================================
# VNet Peering Configuration
# ==============================================================================

variable "create_vnet_peering" {
  description = "Whether to create VNet peering to hub (set false if managing peering elsewhere)"
  type        = bool
  default     = true
}

variable "peering_allow_virtual_network_access" {
  description = "Allow access to the hub VNet"
  type        = bool
  default     = true
}

variable "peering_allow_forwarded_traffic" {
  description = "Allow forwarded traffic from hub (REQUIRED for firewall routing)"
  type        = bool
  default     = true
}

variable "peering_use_remote_gateways" {
  description = "Use hub's VPN Gateway (set to true if hub_has_vpn_gateway = true)"
  type        = bool
  default     = null  # Will be set automatically based on hub_has_vpn_gateway if null
}

# ==============================================================================
# Route Table Configuration
# ==============================================================================

variable "create_route_table" {
  description = "Whether to create a new route table (set false to use hub's default route table)"
  type        = bool
  default     = true
}

variable "route_table_name" {
  description = "Name of the route table for spoke subnets"
  type        = string
  default     = "rt-spoke-to-firewall"
}

variable "disable_bgp_route_propagation" {
  description = "CRITICAL: Set to true if hub has VPN Gateway to prevent route conflicts"
  type        = bool
  default     = null  # Will be set automatically based on hub_has_vpn_gateway if null
}

variable "hub_default_route_table_id" {
  description = "Resource ID of hub's default route table (optional, use instead of creating new route table)"
  type        = string
  default     = null
}

# ==============================================================================
# Tagging
# ==============================================================================

variable "tags" {
  description = "Tags to apply to all spoke resources"
  type        = map(string)
  default = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Purpose     = "Spoke-Network"
  }
}

# ==============================================================================
# Locals for automatic configuration
# ==============================================================================
# These handle VPN Gateway scenarios automatically
# ==============================================================================

locals {
  # Auto-configure based on VPN Gateway presence
  use_remote_gateways = var.peering_use_remote_gateways != null ? var.peering_use_remote_gateways : var.hub_has_vpn_gateway

  # CRITICAL: Disable BGP propagation if hub has VPN Gateway
  disable_bgp = var.disable_bgp_route_propagation != null ? var.disable_bgp_route_propagation : var.hub_has_vpn_gateway

  # Determine which route table to use
  route_table_id = var.create_route_table ? azurerm_route_table.spoke[0].id : var.hub_default_route_table_id
}
