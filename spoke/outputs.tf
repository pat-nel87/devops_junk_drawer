# ==============================================================================
# Spoke Network Outputs
# ==============================================================================

# ==============================================================================
# Resource Group Outputs
# ==============================================================================

output "resource_group_name" {
  description = "Name of the spoke resource group"
  value       = local.resource_group_name
}

output "resource_group_id" {
  description = "ID of the spoke resource group"
  value       = var.create_resource_group ? azurerm_resource_group.spoke[0].id : data.azurerm_resource_group.spoke[0].id
}

output "location" {
  description = "Azure region where spoke resources are deployed"
  value       = var.location
}

# ==============================================================================
# Spoke VNet Outputs
# ==============================================================================

output "spoke_vnet_name" {
  description = "Name of the spoke virtual network"
  value       = azurerm_virtual_network.spoke.name
}

output "spoke_vnet_id" {
  description = "ID of the spoke virtual network"
  value       = azurerm_virtual_network.spoke.id
}

output "spoke_vnet_address_space" {
  description = "Address space of the spoke virtual network"
  value       = azurerm_virtual_network.spoke.address_space
}

# ==============================================================================
# Subnet Outputs
# ==============================================================================

output "subnet_ids" {
  description = "Map of subnet names to subnet IDs"
  value       = { for k, v in azurerm_subnet.spoke : k => v.id }
}

output "subnet_address_prefixes" {
  description = "Map of subnet names to address prefixes"
  value       = { for k, v in azurerm_subnet.spoke : k => v.address_prefixes[0] }
}

# ==============================================================================
# VNet Peering Outputs
# ==============================================================================

output "spoke_to_hub_peering_id" {
  description = "ID of the spoke-to-hub VNet peering"
  value       = var.create_vnet_peering ? azurerm_virtual_network_peering.spoke_to_hub[0].id : null
}

output "hub_to_spoke_peering_id" {
  description = "ID of the hub-to-spoke VNet peering"
  value       = var.create_vnet_peering ? azurerm_virtual_network_peering.hub_to_spoke[0].id : null
}

output "peering_status" {
  description = "Status information about VNet peering"
  value = var.create_vnet_peering ? {
    spoke_to_hub_state       = azurerm_virtual_network_peering.spoke_to_hub[0].peering_state
    hub_to_spoke_state       = azurerm_virtual_network_peering.hub_to_spoke[0].peering_state
    use_remote_gateways      = local.use_remote_gateways
    hub_gateway_transit      = var.hub_has_vpn_gateway
  } : null
}

# ==============================================================================
# Route Table Outputs
# ==============================================================================

output "route_table_id" {
  description = "ID of the spoke route table"
  value       = var.create_route_table ? azurerm_route_table.spoke[0].id : var.hub_default_route_table_id
}

output "route_table_name" {
  description = "Name of the spoke route table"
  value       = var.create_route_table ? azurerm_route_table.spoke[0].name : null
}

output "bgp_route_propagation_disabled" {
  description = "Whether BGP route propagation is disabled (should be true if hub has VPN Gateway)"
  value       = local.disable_bgp
}

# ==============================================================================
# Configuration Summary
# ==============================================================================

output "spoke_configuration" {
  description = "Summary of spoke configuration"
  value = {
    spoke_vnet_name           = azurerm_virtual_network.spoke.name
    spoke_vnet_address        = var.spoke_vnet_address_space
    hub_vnet_name             = var.hub_vnet_name
    firewall_next_hop         = var.firewall_private_ip
    hub_has_vpn_gateway       = var.hub_has_vpn_gateway
    using_remote_gateways     = local.use_remote_gateways
    bgp_propagation_disabled  = local.disable_bgp
    peering_created           = var.create_vnet_peering
    route_table_created       = var.create_route_table
  }
}

# ==============================================================================
# Verification Commands
# ==============================================================================

output "verification_commands" {
  description = "Azure CLI commands to verify spoke deployment"
  value = <<-EOT
    # Verify VNet peering status
    az network vnet peering show \
      --resource-group ${local.resource_group_name} \
      --name ${var.create_vnet_peering ? azurerm_virtual_network_peering.spoke_to_hub[0].name : "N/A"} \
      --vnet-name ${azurerm_virtual_network.spoke.name} \
      --query "peeringState" -o tsv
    # Expected: "Connected"

    # Verify route table
    az network route-table route list \
      --resource-group ${local.resource_group_name} \
      --route-table-name ${var.create_route_table ? azurerm_route_table.spoke[0].name : "N/A"} \
      -o table
    # Should show 0.0.0.0/0 route to ${var.firewall_private_ip}

    # Check effective routes on a VM NIC (replace with your NIC name)
    # az network nic show-effective-route-table \
    #   --resource-group ${local.resource_group_name} \
    #   --name <your-nic-name> \
    #   -o table
    # Should show:
    # - 0.0.0.0/0 -> VirtualAppliance (${var.firewall_private_ip})
    # - Hub VNet range -> VNetPeering
    ${var.hub_has_vpn_gateway ? "# - BGP routes should NOT appear (bgp_propagation_disabled = true)" : ""}
  EOT
}
