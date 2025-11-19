# ============================================================================
# Hub Network Variables
# ============================================================================

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the resource group for hub networking resources"
  type        = string
  default     = "rg-hub-networking"
}

variable "create_resource_group" {
  description = "Whether to create a new resource group or use existing"
  type        = bool
  default     = true
}

# ============================================================================
# Hub VNet Configuration
# ============================================================================

variable "hub_vnet_name" {
  description = "Name of the hub virtual network"
  type        = string
  default     = "vnet-hub"
}

variable "hub_vnet_address_space" {
  description = "Address space for the hub VNet"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "firewall_subnet_address_prefix" {
  description = "Address prefix for AzureFirewallSubnet (minimum /26, recommended /25)"
  type        = string
  default     = "10.0.1.0/26"
}

variable "additional_hub_subnets" {
  description = "Additional subnets in the hub VNet (e.g., GatewaySubnet, BastionSubnet)"
  type = map(object({
    address_prefix = string
  }))
  default = {
    # Example: Uncomment if you need these subnets
    # "GatewaySubnet" = {
    #   address_prefix = "10.0.0.0/27"
    # }
    # "AzureBastionSubnet" = {
    #   address_prefix = "10.0.2.0/27"
    # }
  }
}

# ============================================================================
# Azure Firewall Configuration
# ============================================================================

variable "firewall_name" {
  description = "Name of the Azure Firewall"
  type        = string
  default     = "azfw-hub"
}

variable "firewall_sku_tier" {
  description = "SKU tier for Azure Firewall (Basic, Standard, or Premium)"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.firewall_sku_tier)
    error_message = "Firewall SKU tier must be Basic, Standard, or Premium."
  }
}

variable "firewall_zones" {
  description = "Availability zones for Azure Firewall (empty list for no zones, or [1,2,3] for zone-redundant)"
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "enable_dns_proxy" {
  description = "Enable DNS proxy on the firewall for FQDN filtering"
  type        = bool
  default     = true
}

variable "custom_dns_servers" {
  description = "Custom DNS servers for the firewall (empty list uses Azure DNS)"
  type        = list(string)
  default     = []
}

variable "threat_intelligence_mode" {
  description = "Threat intelligence mode (Off, Alert, or Deny)"
  type        = string
  default     = "Alert"
  validation {
    condition     = contains(["Off", "Alert", "Deny"], var.threat_intelligence_mode)
    error_message = "Threat intelligence mode must be Off, Alert, or Deny."
  }
}

# ============================================================================
# Firewall Policy Rules
# ============================================================================

variable "allowed_source_addresses" {
  description = "Source addresses allowed through the firewall (spoke VNet ranges and P2S VPN client pool)"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12"]  # Include typical P2S ranges
}

variable "allow_all_outbound_internet" {
  description = "Whether to allow all outbound internet traffic (set to false for restrictive rules)"
  type        = bool
  default     = true
}

variable "allowed_destination_fqdns" {
  description = "List of FQDNs allowed through the firewall when not allowing all traffic"
  type        = list(string)
  default = [
    "*.microsoft.com",
    "*.windows.net",
    "*.azure.com"
  ]
}

# ============================================================================
# Public IP Configuration
# ============================================================================

variable "firewall_public_ip_name" {
  description = "Name of the public IP for Azure Firewall"
  type        = string
  default     = "pip-azfw-hub"
}

# ============================================================================
# Route Table Configuration
# ============================================================================

variable "create_default_route_table" {
  description = "Whether to create a default route table for spokes to use"
  type        = bool
  default     = true
}

variable "route_table_name" {
  description = "Name of the route table for spoke subnets"
  type        = string
  default     = "rt-spoke-to-firewall"
}

variable "disable_bgp_route_propagation" {
  description = "Disable BGP route propagation on route table (set to true if using ExpressRoute/VPN to prevent conflicts)"
  type        = bool
  default     = false
}

# ============================================================================
# VPN Gateway Configuration (Point-to-Site)
# ============================================================================

variable "enable_vpn_gateway" {
  description = "Enable P2S VPN Gateway in the hub"
  type        = bool
  default     = false
}

variable "gateway_subnet_address_prefix" {
  description = "Address prefix for GatewaySubnet (minimum /27, recommended /26 or larger)"
  type        = string
  default     = "10.0.0.0/27"
}

variable "vpn_gateway_name" {
  description = "Name of the VPN Gateway"
  type        = string
  default     = "vgw-hub"
}

variable "vpn_gateway_sku" {
  description = "SKU for VPN Gateway (VpnGw1, VpnGw2, VpnGw3, VpnGw1AZ, VpnGw2AZ, VpnGw3AZ)"
  type        = string
  default     = "VpnGw1"
  validation {
    condition     = contains(["VpnGw1", "VpnGw2", "VpnGw3", "VpnGw4", "VpnGw5", "VpnGw1AZ", "VpnGw2AZ", "VpnGw3AZ", "VpnGw4AZ", "VpnGw5AZ"], var.vpn_gateway_sku)
    error_message = "VPN Gateway SKU must be a valid VpnGw SKU."
  }
}

variable "vpn_gateway_generation" {
  description = "Generation of VPN Gateway (Generation1 or Generation2)"
  type        = string
  default     = "Generation1"
  validation {
    condition     = contains(["Generation1", "Generation2"], var.vpn_gateway_generation)
    error_message = "VPN Gateway generation must be Generation1 or Generation2."
  }
}

variable "p2s_client_address_pool" {
  description = "Address pool for P2S VPN clients"
  type        = list(string)
  default     = ["172.16.0.0/24"]
}

variable "vpn_auth_types" {
  description = "Authentication types for P2S VPN (AAD for Entra ID, Certificate, or Radius)"
  type        = list(string)
  default     = ["AAD"]
  validation {
    condition     = alltrue([for auth in var.vpn_auth_types : contains(["AAD", "Certificate", "Radius"], auth)])
    error_message = "VPN auth types must be AAD, Certificate, or Radius."
  }
}

variable "aad_tenant_id" {
  description = "Azure AD (Entra ID) Tenant ID for P2S VPN authentication"
  type        = string
  default     = null
}

variable "aad_audience" {
  description = "Azure AD Application ID (Audience) for VPN authentication"
  type        = string
  default     = null
}

variable "aad_issuer" {
  description = "Azure AD Issuer URL for VPN authentication"
  type        = string
  default     = null
}

variable "vpn_client_protocols" {
  description = "VPN client protocols (OpenVPN and/or IkeV2)"
  type        = list(string)
  default     = ["OpenVPN"]
  validation {
    condition     = alltrue([for proto in var.vpn_client_protocols : contains(["OpenVPN", "IkeV2"], proto)])
    error_message = "VPN client protocols must be OpenVPN or IkeV2."
  }
}

variable "enable_active_active_vpn" {
  description = "Enable active-active VPN Gateway (requires two public IPs)"
  type        = bool
  default     = false
}

variable "vpn_gateway_public_ip_name" {
  description = "Name of the public IP for VPN Gateway"
  type        = string
  default     = "pip-vgw-hub"
}

variable "vpn_gateway_zones" {
  description = "Availability zones for VPN Gateway (only for AZ SKUs)"
  type        = list(string)
  default     = []
}

# ============================================================================
# Optional Features
# ============================================================================

variable "enable_forced_tunneling" {
  description = "Enable forced tunneling (requires management subnet and public IP)"
  type        = bool
  default     = false
}

variable "firewall_management_subnet_address_prefix" {
  description = "Address prefix for AzureFirewallManagementSubnet (only used if forced tunneling is enabled)"
  type        = string
  default     = "10.0.3.0/26"
}

variable "enable_nat_gateway_for_firewall" {
  description = "Enable NAT Gateway on AzureFirewallSubnet for additional SNAT capacity"
  type        = bool
  default     = false
}

variable "nat_gateway_public_ip_count" {
  description = "Number of public IPs for NAT Gateway (only used if enable_nat_gateway_for_firewall is true)"
  type        = number
  default     = 1
}

# ============================================================================
# Monitoring and Diagnostics
# ============================================================================

variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings for Azure Firewall"
  type        = bool
  default     = false
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for diagnostic settings (required if enable_diagnostic_settings is true)"
  type        = string
  default     = null
}

# ============================================================================
# Tagging
# ============================================================================

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Purpose     = "Hub-Firewall"
  }
}
