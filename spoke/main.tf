# ==============================================================================
# Spoke Network Resources
# ==============================================================================
# This spoke connects to a hub network with Azure Firewall and optional VPN Gateway
# All internet-bound traffic is routed through the hub's Azure Firewall
# ==============================================================================

# ==============================================================================
# Resource Group
# ==============================================================================

resource "azurerm_resource_group" "spoke" {
  count    = var.create_resource_group ? 1 : 0
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

data "azurerm_resource_group" "spoke" {
  count = var.create_resource_group ? 0 : 1
  name  = var.resource_group_name
}

locals {
  resource_group_name = var.create_resource_group ? azurerm_resource_group.spoke[0].name : data.azurerm_resource_group.spoke[0].name
}

# ==============================================================================
# Spoke Virtual Network
# ==============================================================================

resource "azurerm_virtual_network" "spoke" {
  name                = var.spoke_vnet_name
  location            = var.location
  resource_group_name = local.resource_group_name
  address_space       = var.spoke_vnet_address_space
  tags                = var.tags
}

# ==============================================================================
# Spoke Subnets
# ==============================================================================

resource "azurerm_subnet" "spoke" {
  for_each             = var.spoke_subnets
  name                 = each.key
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [each.value.address_prefix]
}

# ==============================================================================
# VNet Peering: Spoke to Hub
# ==============================================================================
# CRITICAL SETTINGS:
# - allow_forwarded_traffic MUST be true for firewall routing
# - use_remote_gateways MUST be true if hub has VPN Gateway
# ==============================================================================

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  count                        = var.create_vnet_peering ? 1 : 0
  name                         = "${var.spoke_vnet_name}-to-${var.hub_vnet_name}"
  resource_group_name          = local.resource_group_name
  virtual_network_name         = azurerm_virtual_network.spoke.name
  remote_virtual_network_id    = var.hub_vnet_id
  allow_virtual_network_access = var.peering_allow_virtual_network_access
  allow_forwarded_traffic      = var.peering_allow_forwarded_traffic
  allow_gateway_transit        = false
  use_remote_gateways          = local.use_remote_gateways

  tags = var.tags

  # Wait for spoke VNet to be fully created
  depends_on = [azurerm_virtual_network.spoke]
}

# ==============================================================================
# VNet Peering: Hub to Spoke
# ==============================================================================
# CRITICAL SETTINGS:
# - allow_forwarded_traffic MUST be true for firewall routing
# - allow_gateway_transit MUST be true if hub has VPN Gateway
# ==============================================================================

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  count                        = var.create_vnet_peering ? 1 : 0
  name                         = "${var.hub_vnet_name}-to-${var.spoke_vnet_name}"
  resource_group_name          = var.hub_resource_group_name
  virtual_network_name         = var.hub_vnet_name
  remote_virtual_network_id    = azurerm_virtual_network.spoke.id
  allow_virtual_network_access = var.peering_allow_virtual_network_access
  allow_forwarded_traffic      = var.peering_allow_forwarded_traffic
  allow_gateway_transit        = var.hub_has_vpn_gateway  # Must be true if hub has VPN Gateway
  use_remote_gateways          = false

  tags = var.tags

  # Wait for spoke VNet to be fully created
  depends_on = [azurerm_virtual_network.spoke]
}

# ==============================================================================
# Route Table for Spoke Subnets
# ==============================================================================
# Routes all internet-bound traffic (0.0.0.0/0) to Azure Firewall
# CRITICAL: disable_bgp_route_propagation MUST be true if hub has VPN Gateway
# ==============================================================================

resource "azurerm_route_table" "spoke" {
  count                         = var.create_route_table ? 1 : 0
  name                          = var.route_table_name
  location                      = var.location
  resource_group_name           = local.resource_group_name
  disable_bgp_route_propagation = local.disable_bgp
  tags                          = var.tags
}

# ==============================================================================
# Default Route to Azure Firewall
# ==============================================================================
# Routes all internet traffic through the hub's Azure Firewall
# next_hop_type MUST be "VirtualAppliance"
# next_hop_in_ip_address is the firewall's private IP
# ==============================================================================

resource "azurerm_route" "default_to_firewall" {
  count                  = var.create_route_table ? 1 : 0
  name                   = "default-via-hub-firewall"
  resource_group_name    = local.resource_group_name
  route_table_name       = azurerm_route_table.spoke[0].name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = var.firewall_private_ip
}

# ==============================================================================
# Route Table Associations
# ==============================================================================
# Associate route table only with subnets that have associate_route_table = true
# ==============================================================================

resource "azurerm_subnet_route_table_association" "spoke" {
  for_each = {
    for k, v in var.spoke_subnets : k => v
    if v.associate_route_table
  }

  subnet_id      = azurerm_subnet.spoke[each.key].id
  route_table_id = local.route_table_id

  # Ensure route table exists before associating
  depends_on = [
    azurerm_route_table.spoke,
    azurerm_route.default_to_firewall
  ]
}
