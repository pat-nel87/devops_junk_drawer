# ============================================================================
# Resource Group
# ============================================================================

resource "azurerm_resource_group" "hub" {
  count    = var.create_resource_group ? 1 : 0
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

data "azurerm_resource_group" "hub" {
  count = var.create_resource_group ? 0 : 1
  name  = var.resource_group_name
}

locals {
  resource_group_name = var.create_resource_group ? azurerm_resource_group.hub[0].name : data.azurerm_resource_group.hub[0].name
}

# ============================================================================
# Hub Virtual Network
# ============================================================================

resource "azurerm_virtual_network" "hub" {
  name                = var.hub_vnet_name
  location            = var.location
  resource_group_name = local.resource_group_name
  address_space       = var.hub_vnet_address_space
  tags                = var.tags
}

# ============================================================================
# AzureFirewallSubnet - MUST be named exactly "AzureFirewallSubnet"
# ============================================================================

resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"  # MUST be this exact name (case-sensitive)
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.firewall_subnet_address_prefix]
}

# ============================================================================
# AzureFirewallManagementSubnet - Only for forced tunneling
# ============================================================================

resource "azurerm_subnet" "firewall_management" {
  count                = var.enable_forced_tunneling ? 1 : 0
  name                 = "AzureFirewallManagementSubnet"  # MUST be this exact name
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.firewall_management_subnet_address_prefix]
}

# ============================================================================
# GatewaySubnet - MUST be named exactly "GatewaySubnet" for VPN Gateway
# ============================================================================

resource "azurerm_subnet" "gateway" {
  count                = var.enable_vpn_gateway ? 1 : 0
  name                 = "GatewaySubnet"  # MUST be this exact name (case-sensitive)
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.gateway_subnet_address_prefix]
}

# ============================================================================
# Additional Hub Subnets (e.g., BastionSubnet)
# ============================================================================

resource "azurerm_subnet" "additional" {
  for_each             = var.additional_hub_subnets
  name                 = each.key
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [each.value.address_prefix]
}

# ============================================================================
# Public IP for VPN Gateway
# ============================================================================

resource "azurerm_public_ip" "vpn_gateway" {
  count               = var.enable_vpn_gateway ? 1 : 0
  name                = var.vpn_gateway_public_ip_name
  location            = var.location
  resource_group_name = local.resource_group_name
  allocation_method   = "Static"  # MUST be Static for VPN Gateway
  sku                 = "Standard"  # MUST be Standard for VPN Gateway
  zones               = var.vpn_gateway_zones
  tags                = var.tags
}

resource "azurerm_public_ip" "vpn_gateway_secondary" {
  count               = var.enable_vpn_gateway && var.enable_active_active_vpn ? 1 : 0
  name                = "${var.vpn_gateway_public_ip_name}-secondary"
  location            = var.location
  resource_group_name = local.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.vpn_gateway_zones
  tags                = var.tags
}

# ============================================================================
# Public IP for Azure Firewall
# ============================================================================

resource "azurerm_public_ip" "firewall" {
  name                = var.firewall_public_ip_name
  location            = var.location
  resource_group_name = local.resource_group_name
  allocation_method   = "Static"  # MUST be Static for Azure Firewall
  sku                 = "Standard"  # MUST be Standard for Azure Firewall
  zones               = var.firewall_zones
  tags                = var.tags
}

# ============================================================================
# Public IP for Firewall Management (Forced Tunneling)
# ============================================================================

resource "azurerm_public_ip" "firewall_management" {
  count               = var.enable_forced_tunneling ? 1 : 0
  name                = "${var.firewall_public_ip_name}-management"
  location            = var.location
  resource_group_name = local.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.firewall_zones
  tags                = var.tags
}

# ============================================================================
# Azure Firewall Policy
# ============================================================================

resource "azurerm_firewall_policy" "hub" {
  name                     = "fwpol-${var.hub_vnet_name}"
  resource_group_name      = local.resource_group_name
  location                 = var.location
  sku                      = var.firewall_sku_tier
  threat_intelligence_mode = var.threat_intelligence_mode

  dns {
    proxy_enabled = var.enable_dns_proxy
    servers       = var.custom_dns_servers
  }

  tags = var.tags
}

# ============================================================================
# Firewall Policy Rule Collection Group
# ============================================================================

resource "azurerm_firewall_policy_rule_collection_group" "network_rules" {
  name               = "DefaultNetworkRuleCollectionGroup"
  firewall_policy_id = azurerm_firewall_policy.hub.id
  priority           = 100

  # Network Rules - Basic outbound connectivity
  network_rule_collection {
    name     = "AllowOutboundInternet"
    priority = 100
    action   = "Allow"

    rule {
      name                  = "AllowHTTPSHTTP"
      protocols             = ["TCP"]
      source_addresses      = var.allowed_source_addresses
      destination_addresses = ["*"]
      destination_ports     = ["80", "443"]
    }

    rule {
      name                  = "AllowDNS"
      protocols             = ["UDP"]
      source_addresses      = var.allowed_source_addresses
      destination_addresses = ["*"]
      destination_ports     = ["53"]
    }

    rule {
      name                  = "AllowAzureServices"
      protocols             = ["TCP"]
      source_addresses      = var.allowed_source_addresses
      destination_addresses = ["AzureCloud"]  # Service Tag for all Azure services
      destination_ports     = ["443"]
    }
  }

  # Application Rules - FQDN-based filtering
  application_rule_collection {
    name     = "AllowWebTraffic"
    priority = 200
    action   = "Allow"

    rule {
      name             = var.allow_all_outbound_internet ? "AllowAllHTTPS" : "AllowSpecificFQDNs"
      source_addresses = var.allowed_source_addresses

      protocols {
        type = "Https"
        port = 443
      }

      protocols {
        type = "Http"
        port = 80
      }

      destination_fqdns = var.allow_all_outbound_internet ? ["*"] : var.allowed_destination_fqdns
    }
  }
}

# ============================================================================
# Azure Firewall
# ============================================================================

resource "azurerm_firewall" "hub" {
  name                = var.firewall_name
  location            = var.location
  resource_group_name = local.resource_group_name
  sku_name            = "AZFW_VNet"  # For traditional VNet deployment (not vWAN)
  sku_tier            = var.firewall_sku_tier  # MUST match firewall policy SKU
  firewall_policy_id  = azurerm_firewall_policy.hub.id
  zones               = var.firewall_zones

  # Primary IP Configuration - Attaches to AzureFirewallSubnet
  ip_configuration {
    name                 = "primary-ipconfig"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }

  # Management IP Configuration - Only for forced tunneling
  dynamic "management_ip_configuration" {
    for_each = var.enable_forced_tunneling ? [1] : []
    content {
      name                 = "management-ipconfig"
      subnet_id            = azurerm_subnet.firewall_management[0].id
      public_ip_address_id = azurerm_public_ip.firewall_management[0].id
    }
  }

  tags = var.tags
}

# ============================================================================
# NAT Gateway for Additional SNAT Capacity (Optional)
# ============================================================================

resource "azurerm_public_ip" "nat_gateway" {
  count               = var.enable_nat_gateway_for_firewall ? var.nat_gateway_public_ip_count : 0
  name                = "pip-nat-firewall-${count.index + 1}"
  location            = var.location
  resource_group_name = local.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.firewall_zones
  tags                = var.tags
}

resource "azurerm_nat_gateway" "firewall" {
  count               = var.enable_nat_gateway_for_firewall ? 1 : 0
  name                = "nat-firewall-outbound"
  location            = var.location
  resource_group_name = local.resource_group_name
  sku_name            = "Standard"
  zones               = var.firewall_zones
  tags                = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "firewall" {
  count                = var.enable_nat_gateway_for_firewall ? var.nat_gateway_public_ip_count : 0
  nat_gateway_id       = azurerm_nat_gateway.firewall[0].id
  public_ip_address_id = azurerm_public_ip.nat_gateway[count.index].id
}

resource "azurerm_subnet_nat_gateway_association" "firewall" {
  count          = var.enable_nat_gateway_for_firewall ? 1 : 0
  subnet_id      = azurerm_subnet.firewall.id
  nat_gateway_id = azurerm_nat_gateway.firewall[0].id
}

# ============================================================================
# VPN Gateway (Point-to-Site with Entra ID)
# ============================================================================

# Locals for Entra ID VPN Configuration
locals {
  # Default Azure VPN Client Application IDs per Azure region
  vpn_aad_tenant    = var.aad_tenant_id != null ? var.aad_tenant_id : data.azurerm_client_config.current.tenant_id
  vpn_aad_audience  = var.aad_audience != null ? var.aad_audience : "41b23e61-6c1e-4545-b367-cd054e0ed4b4"  # Azure VPN Client App ID
  vpn_aad_issuer    = var.aad_issuer != null ? var.aad_issuer : "https://sts.windows.net/${local.vpn_aad_tenant}/"
}

data "azurerm_client_config" "current" {}

resource "azurerm_virtual_network_gateway" "hub" {
  count               = var.enable_vpn_gateway ? 1 : 0
  name                = var.vpn_gateway_name
  location            = var.location
  resource_group_name = local.resource_group_name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = var.vpn_gateway_sku
  generation          = var.vpn_gateway_generation
  active_active       = var.enable_active_active_vpn

  # Primary IP Configuration
  ip_configuration {
    name                          = "primary-ipconfig"
    public_ip_address_id          = azurerm_public_ip.vpn_gateway[0].id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway[0].id
  }

  # Secondary IP Configuration (Active-Active only)
  dynamic "ip_configuration" {
    for_each = var.enable_active_active_vpn ? [1] : []
    content {
      name                          = "secondary-ipconfig"
      public_ip_address_id          = azurerm_public_ip.vpn_gateway_secondary[0].id
      private_ip_address_allocation = "Dynamic"
      subnet_id                     = azurerm_subnet.gateway[0].id
    }
  }

  # Point-to-Site VPN Configuration
  vpn_client_configuration {
    address_space        = var.p2s_client_address_pool
    vpn_client_protocols = var.vpn_client_protocols
    vpn_auth_types       = var.vpn_auth_types

    # Entra ID (Azure AD) Authentication
    dynamic "aad_authentication" {
      for_each = contains(var.vpn_auth_types, "AAD") ? [1] : []
      content {
        tenant   = local.vpn_aad_issuer
        audience = local.vpn_aad_audience
        issuer   = local.vpn_aad_issuer
      }
    }
  }

  tags = var.tags
}

# ============================================================================
# Route Table for Spoke Subnets
# ============================================================================

resource "azurerm_route_table" "spoke_default" {
  count                         = var.create_default_route_table ? 1 : 0
  name                          = var.route_table_name
  location                      = var.location
  resource_group_name           = local.resource_group_name
  disable_bgp_route_propagation = var.disable_bgp_route_propagation
  tags                          = var.tags
}

resource "azurerm_route" "default_to_firewall" {
  count                  = var.create_default_route_table ? 1 : 0
  name                   = "default-via-firewall"
  resource_group_name    = local.resource_group_name
  route_table_name       = azurerm_route_table.spoke_default[0].name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.hub.ip_configuration[0].private_ip_address
}

# ============================================================================
# Diagnostic Settings (Optional)
# ============================================================================

resource "azurerm_monitor_diagnostic_setting" "firewall" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "diag-${var.firewall_name}"
  target_resource_id         = azurerm_firewall.hub.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "AzureFirewallApplicationRule"
  }

  enabled_log {
    category = "AzureFirewallNetworkRule"
  }

  enabled_log {
    category = "AzureFirewallDnsProxy"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "vpn_gateway" {
  count                      = var.enable_diagnostic_settings && var.enable_vpn_gateway ? 1 : 0
  name                       = "diag-${var.vpn_gateway_name}"
  target_resource_id         = azurerm_virtual_network_gateway.hub[0].id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "GatewayDiagnosticLog"
  }

  enabled_log {
    category = "TunnelDiagnosticLog"
  }

  enabled_log {
    category = "RouteDiagnosticLog"
  }

  enabled_log {
    category = "IKEDiagnosticLog"
  }

  enabled_log {
    category = "P2SDiagnosticLog"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
