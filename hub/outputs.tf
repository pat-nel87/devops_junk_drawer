# ============================================================================
# Resource Group Outputs
# ============================================================================

output "resource_group_name" {
  description = "Name of the hub resource group"
  value       = local.resource_group_name
}

output "resource_group_id" {
  description = "ID of the hub resource group"
  value       = var.create_resource_group ? azurerm_resource_group.hub[0].id : data.azurerm_resource_group.hub[0].id
}

output "location" {
  description = "Azure region where hub resources are deployed"
  value       = var.location
}

# ============================================================================
# Hub VNet Outputs
# ============================================================================

output "hub_vnet_name" {
  description = "Name of the hub virtual network"
  value       = azurerm_virtual_network.hub.name
}

output "hub_vnet_id" {
  description = "ID of the hub virtual network"
  value       = azurerm_virtual_network.hub.id
}

output "hub_vnet_address_space" {
  description = "Address space of the hub virtual network"
  value       = azurerm_virtual_network.hub.address_space
}

# ============================================================================
# Azure Firewall Outputs
# ============================================================================

output "firewall_name" {
  description = "Name of the Azure Firewall"
  value       = azurerm_firewall.hub.name
}

output "firewall_id" {
  description = "ID of the Azure Firewall"
  value       = azurerm_firewall.hub.id
}

output "firewall_private_ip" {
  description = "Private IP address of Azure Firewall (use this as next hop in spoke route tables)"
  value       = azurerm_firewall.hub.ip_configuration[0].private_ip_address
}

output "firewall_public_ip" {
  description = "Public IP address of Azure Firewall (used for outbound SNAT)"
  value       = azurerm_public_ip.firewall.ip_address
}

output "firewall_public_ip_id" {
  description = "ID of the firewall's public IP address"
  value       = azurerm_public_ip.firewall.id
}

# ============================================================================
# Firewall Policy Outputs
# ============================================================================

output "firewall_policy_id" {
  description = "ID of the Azure Firewall Policy"
  value       = azurerm_firewall_policy.hub.id
}

output "firewall_policy_name" {
  description = "Name of the Azure Firewall Policy"
  value       = azurerm_firewall_policy.hub.name
}

# ============================================================================
# Route Table Outputs
# ============================================================================

output "default_route_table_id" {
  description = "ID of the default route table for spoke subnets (if created)"
  value       = var.create_default_route_table ? azurerm_route_table.spoke_default[0].id : null
}

output "default_route_table_name" {
  description = "Name of the default route table for spoke subnets (if created)"
  value       = var.create_default_route_table ? azurerm_route_table.spoke_default[0].name : null
}

# ============================================================================
# Subnet Outputs
# ============================================================================

output "firewall_subnet_id" {
  description = "ID of the AzureFirewallSubnet"
  value       = azurerm_subnet.firewall.id
}

output "firewall_subnet_address_prefix" {
  description = "Address prefix of the AzureFirewallSubnet"
  value       = azurerm_subnet.firewall.address_prefixes[0]
}

output "additional_subnet_ids" {
  description = "IDs of additional hub subnets"
  value       = { for k, v in azurerm_subnet.additional : k => v.id }
}

# ============================================================================
# NAT Gateway Outputs (if enabled)
# ============================================================================

output "nat_gateway_id" {
  description = "ID of the NAT Gateway (if enabled)"
  value       = var.enable_nat_gateway_for_firewall ? azurerm_nat_gateway.firewall[0].id : null
}

output "nat_gateway_public_ips" {
  description = "Public IP addresses of the NAT Gateway (if enabled)"
  value       = var.enable_nat_gateway_for_firewall ? [for pip in azurerm_public_ip.nat_gateway : pip.ip_address] : []
}

# ============================================================================
# VPN Gateway Outputs (if enabled)
# ============================================================================

output "vpn_gateway_id" {
  description = "ID of the VPN Gateway (if enabled)"
  value       = var.enable_vpn_gateway ? azurerm_virtual_network_gateway.hub[0].id : null
}

output "vpn_gateway_name" {
  description = "Name of the VPN Gateway (if enabled)"
  value       = var.enable_vpn_gateway ? azurerm_virtual_network_gateway.hub[0].name : null
}

output "vpn_gateway_public_ip" {
  description = "Public IP address of the VPN Gateway (if enabled)"
  value       = var.enable_vpn_gateway ? azurerm_public_ip.vpn_gateway[0].ip_address : null
}

output "vpn_gateway_public_ip_secondary" {
  description = "Secondary public IP address of the VPN Gateway (if active-active enabled)"
  value       = var.enable_vpn_gateway && var.enable_active_active_vpn ? azurerm_public_ip.vpn_gateway_secondary[0].ip_address : null
}

output "p2s_client_address_pool" {
  description = "P2S VPN client address pool"
  value       = var.enable_vpn_gateway ? var.p2s_client_address_pool : null
}

output "gateway_subnet_id" {
  description = "ID of the GatewaySubnet (if VPN Gateway enabled)"
  value       = var.enable_vpn_gateway ? azurerm_subnet.gateway[0].id : null
}

output "vpn_aad_configuration" {
  description = "Entra ID (Azure AD) configuration for P2S VPN"
  value = var.enable_vpn_gateway && contains(var.vpn_auth_types, "AAD") ? {
    tenant_id = local.vpn_aad_tenant
    audience  = local.vpn_aad_audience
    issuer    = local.vpn_aad_issuer
  } : null
}

# ============================================================================
# Information for Spoke Integration
# ============================================================================

output "spoke_integration_info" {
  description = "Essential information for integrating spoke VNets"
  value = {
    hub_vnet_id                = azurerm_virtual_network.hub.id
    hub_vnet_name              = azurerm_virtual_network.hub.name
    firewall_private_ip        = azurerm_firewall.hub.ip_configuration[0].private_ip_address
    default_route_table_id     = var.create_default_route_table ? azurerm_route_table.spoke_default[0].id : null
    resource_group_name        = local.resource_group_name
    location                   = var.location
    has_vpn_gateway            = var.enable_vpn_gateway
    allow_gateway_transit      = var.enable_vpn_gateway  # Set to true on hub peering if VPN gateway exists
    use_remote_gateways        = var.enable_vpn_gateway  # Set to true on spoke peering if VPN gateway exists
  }
}

# ============================================================================
# Verification and Testing Outputs
# ============================================================================

output "deployment_verification" {
  description = "Information to verify the deployment"
  value = {
    firewall_provisioning_state = azurerm_firewall.hub.virtual_hub
    firewall_sku                = "${azurerm_firewall.hub.sku_name} / ${azurerm_firewall.hub.sku_tier}"
    firewall_zones              = var.firewall_zones
    dns_proxy_enabled           = var.enable_dns_proxy
    threat_intelligence_mode    = var.threat_intelligence_mode
    forced_tunneling_enabled    = var.enable_forced_tunneling
    nat_gateway_enabled         = var.enable_nat_gateway_for_firewall
    vpn_gateway_enabled         = var.enable_vpn_gateway
    vpn_gateway_sku             = var.enable_vpn_gateway ? var.vpn_gateway_sku : null
    p2s_client_pool             = var.enable_vpn_gateway ? var.p2s_client_address_pool : null
    vpn_auth_type               = var.enable_vpn_gateway ? var.vpn_auth_types : null
  }
}

# ============================================================================
# Azure CLI Commands for Verification
# ============================================================================

output "verification_commands" {
  description = "Azure CLI commands to verify the deployment"
  value = var.enable_vpn_gateway ? <<-EOT
    # Check firewall provisioning state
    az network firewall show --resource-group ${local.resource_group_name} --name ${azurerm_firewall.hub.name} --query "provisioningState" -o tsv

    # Get firewall private IP
    az network firewall show --resource-group ${local.resource_group_name} --name ${azurerm_firewall.hub.name} --query "ipConfigurations[0].privateIpAddress" -o tsv

    # Get firewall public IP
    az network public-ip show --resource-group ${local.resource_group_name} --name ${azurerm_public_ip.firewall.name} --query "ipAddress" -o tsv

    # Check VPN Gateway provisioning state
    az network vnet-gateway show --resource-group ${local.resource_group_name} --name ${var.vpn_gateway_name} --query "provisioningState" -o tsv

    # Get VPN Gateway public IP
    az network public-ip show --resource-group ${local.resource_group_name} --name ${var.vpn_gateway_public_ip_name} --query "ipAddress" -o tsv

    # Get P2S VPN client configuration (download VPN client)
    az network vnet-gateway vpn-client generate --resource-group ${local.resource_group_name} --name ${var.vpn_gateway_name} --processor-architecture Amd64

    # Verify effective routes (replace with your spoke VM NIC name)
    # az network nic show-effective-route-table --resource-group <spoke-rg> --name <nic-name> -o table
  EOT
  : <<-EOT
    # Check firewall provisioning state
    az network firewall show --resource-group ${local.resource_group_name} --name ${azurerm_firewall.hub.name} --query "provisioningState" -o tsv

    # Get firewall private IP
    az network firewall show --resource-group ${local.resource_group_name} --name ${azurerm_firewall.hub.name} --query "ipConfigurations[0].privateIpAddress" -o tsv

    # Get firewall public IP
    az network public-ip show --resource-group ${local.resource_group_name} --name ${azurerm_public_ip.firewall.name} --query "ipAddress" -o tsv

    # Verify effective routes (replace with your spoke VM NIC name)
    # az network nic show-effective-route-table --resource-group <spoke-rg> --name <nic-name> -o table
  EOT
}
