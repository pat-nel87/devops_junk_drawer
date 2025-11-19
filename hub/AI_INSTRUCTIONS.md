# AI Assistant Instructions for Hub Network Module

## CRITICAL TERRAFORM VERSION CONSTRAINT

**MUST USE EXACTLY: azurerm provider version 3.117.1**

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 3.117.1"  # EXACT version - DO NOT CHANGE
    }
  }
}
```

**Why this matters:** This code is designed for and tested with azurerm provider 3.117.1 specifically. Different versions may have breaking changes in resource schemas or behavior.

## Hub Architecture Overview

This is a **HUB** network in a hub-and-spoke topology:

```
Spoke VNets → VNet Peering → HUB VNet → Azure Firewall → Internet
                                ↓
                          VPN Gateway (optional)
                                ↓
                         P2S VPN Clients
```

### Hub Components

1. **Hub VNet** - Central network (e.g., 10.0.0.0/16)
2. **Azure Firewall** - Inspects and SNATs outbound traffic
3. **AzureFirewallSubnet** - MUST be named exactly "AzureFirewallSubnet" (case-sensitive), minimum /26
4. **Firewall Policy** - Rule collections (network and application rules)
5. **VPN Gateway** (optional) - Point-to-Site VPN with Entra ID authentication
6. **GatewaySubnet** (if VPN) - MUST be named exactly "GatewaySubnet", minimum /27
7. **Route Table** - Default route table for spokes (0.0.0.0/0 → Firewall)

## Critical Naming Requirements

### Exact Names Required (Case-Sensitive)

- **AzureFirewallSubnet** - For Azure Firewall (MUST be this exact name)
- **GatewaySubnet** - For VPN Gateway (MUST be this exact name if using VPN)
- **AzureFirewallManagementSubnet** - For forced tunneling (MUST be this exact name if using forced tunneling)

### Why These Names Matter

Azure has hard-coded requirements for these subnet names. Using different names will cause deployment failures.

## Resource Dependencies

**CRITICAL DEPLOYMENT ORDER:**

1. Public IP (Standard SKU, Static allocation)
2. Firewall Policy
3. Firewall Policy Rule Collection Group (optional)
4. Azure Firewall (references Public IP + Policy)
5. Route Table (references Firewall private IP)
6. VPN Gateway (if enabled) - deploys in parallel to firewall

## Azure Firewall Requirements

### Public IP Requirements

```hcl
resource "azurerm_public_ip" "firewall" {
  allocation_method = "Static"  # MUST be Static
  sku               = "Standard" # MUST be Standard
  zones             = ["1", "2", "3"]  # Optional, for zone-redundancy
}
```

### Firewall SKU Matching

```hcl
# Firewall Policy SKU MUST match Firewall SKU
resource "azurerm_firewall_policy" "hub" {
  sku = "Standard"  # Basic, Standard, or Premium
}

resource "azurerm_firewall" "hub" {
  sku_tier = "Standard"  # MUST match policy SKU
}
```

### Firewall Subnet

```hcl
resource "azurerm_subnet" "firewall" {
  name             = "AzureFirewallSubnet"  # EXACT name required
  address_prefixes = ["10.0.1.0/26"]  # Minimum /26, recommended /25
}
```

**CRITICAL:**
- Never associate a route table with AzureFirewallSubnet
- Never associate an NSG with AzureFirewallSubnet

## VPN Gateway Requirements

### Entra ID (Azure AD) Authentication

Default configuration uses Azure VPN Client App ID:

```hcl
locals {
  vpn_aad_tenant   = data.azurerm_client_config.current.tenant_id
  vpn_aad_audience = "41b23e61-6c1e-4545-b367-cd054e0ed4b4"  # Azure VPN Client
  vpn_aad_issuer   = "https://sts.windows.net/${local.vpn_aad_tenant}/"
}
```

### Gateway Subnet

```hcl
resource "azurerm_subnet" "gateway" {
  name             = "GatewaySubnet"  # EXACT name required
  address_prefixes = ["10.0.0.0/27"]  # Minimum /27, recommended /26
}
```

**CRITICAL:**
- Never associate a route table with GatewaySubnet
- Never associate an NSG with GatewaySubnet

### VPN Gateway Configuration

```hcl
resource "azurerm_virtual_network_gateway" "hub" {
  type         = "Vpn"
  vpn_type     = "RouteBased"
  sku          = "VpnGw1"  # VpnGw1, VpnGw2, VpnGw3, or AZ variants
  generation   = "Generation1"  # or Generation2

  vpn_client_configuration {
    address_space        = ["172.16.0.0/24"]  # P2S client pool
    vpn_client_protocols = ["OpenVPN"]
    vpn_auth_types       = ["AAD"]
  }
}
```

## Routing Configuration

### Route Table for Spokes

```hcl
resource "azurerm_route_table" "spoke_default" {
  disable_bgp_route_propagation = var.hub_has_vpn_gateway  # TRUE if VPN Gateway exists
}

resource "azurerm_route" "default_to_firewall" {
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"  # MUST be VirtualAppliance
  next_hop_in_ip_address = azurerm_firewall.hub.ip_configuration[0].private_ip_address
}
```

**CRITICAL:** If VPN Gateway exists, `disable_bgp_route_propagation` MUST be `true` to prevent BGP routes from conflicting with UDR.

## Firewall Rules

### Network Rules

```hcl
network_rule_collection {
  name     = "AllowOutbound"
  priority = 100
  action   = "Allow"

  rule {
    name                  = "AllowHTTPS"
    protocols             = ["TCP"]
    source_addresses      = ["10.0.0.0/8"]  # Include P2S pool if VPN Gateway exists
    destination_addresses = ["*"]
    destination_ports     = ["443"]
  }
}
```

### Application Rules

```hcl
application_rule_collection {
  name     = "AllowWeb"
  priority = 200
  action   = "Allow"

  rule {
    name             = "AllowHTTPS"
    source_addresses = ["10.0.0.0/8"]

    protocols {
      type = "Https"
      port = 443
    }

    destination_fqdns = ["*"]  # or specific FQDNs
  }
}
```

## Common Patterns

### Get Firewall Private IP

```hcl
output "firewall_private_ip" {
  value = azurerm_firewall.hub.ip_configuration[0].private_ip_address
}
```

### Conditional VPN Gateway Resources

```hcl
resource "azurerm_subnet" "gateway" {
  count = var.enable_vpn_gateway ? 1 : 0
  # ...
}

resource "azurerm_virtual_network_gateway" "hub" {
  count = var.enable_vpn_gateway ? 1 : 0
  # ...
}
```

## Spoke Integration Outputs

Provide these outputs for spoke modules:

```hcl
output "spoke_integration_info" {
  value = {
    hub_vnet_id                = azurerm_virtual_network.hub.id
    hub_vnet_name              = azurerm_virtual_network.hub.name
    firewall_private_ip        = azurerm_firewall.hub.ip_configuration[0].private_ip_address
    default_route_table_id     = azurerm_route_table.spoke_default[0].id
    has_vpn_gateway            = var.enable_vpn_gateway
    allow_gateway_transit      = var.enable_vpn_gateway
    use_remote_gateways        = var.enable_vpn_gateway
    resource_group_name        = local.resource_group_name
    location                   = var.location
  }
}
```

## Common Mistakes to Avoid

1. **Wrong subnet names** - "AzureFirewallSubnet" and "GatewaySubnet" are exact names
2. **Route table on special subnets** - Never add route tables to AzureFirewallSubnet or GatewaySubnet
3. **NSG on special subnets** - Never add NSGs to AzureFirewallSubnet or GatewaySubnet
4. **SKU mismatch** - Firewall SKU tier must match Firewall Policy SKU
5. **Public IP SKU** - Must be Standard and Static for both Firewall and VPN Gateway
6. **BGP propagation** - Must disable BGP route propagation on spoke route tables if VPN Gateway exists
7. **Wrong next hop type** - Routes to firewall must use "VirtualAppliance", not "Internet"

## Deployment Timeline

- Firewall: 5-10 minutes
- VPN Gateway: 30-40 minutes
- Total (with VPN): ~50 minutes (they deploy in parallel)

## Example Code Patterns

### Firewall with Policy

```hcl
resource "azurerm_firewall_policy" "hub" {
  name                     = "fwpol-hub"
  sku                      = "Standard"
  threat_intelligence_mode = "Alert"

  dns {
    proxy_enabled = true
  }
}

resource "azurerm_firewall" "hub" {
  name                = "azfw-hub"
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"  # Match policy SKU
  firewall_policy_id  = azurerm_firewall_policy.hub.id

  ip_configuration {
    name                 = "ipconfig1"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }
}
```

### P2S VPN with Entra ID

```hcl
resource "azurerm_virtual_network_gateway" "hub" {
  type               = "Vpn"
  vpn_type           = "RouteBased"
  sku                = "VpnGw1"
  generation         = "Generation1"

  ip_configuration {
    subnet_id            = azurerm_subnet.gateway.id
    public_ip_address_id = azurerm_public_ip.vpn_gateway.id
  }

  vpn_client_configuration {
    address_space        = ["172.16.0.0/24"]
    vpn_client_protocols = ["OpenVPN"]
    vpn_auth_types       = ["AAD"]

    aad_authentication {
      tenant   = "https://sts.windows.net/${data.azurerm_client_config.current.tenant_id}/"
      audience = "41b23e61-6c1e-4545-b367-cd054e0ed4b4"
      issuer   = "https://sts.windows.net/${data.azurerm_client_config.current.tenant_id}/"
    }
  }
}
```

## Testing and Verification

### Check Firewall Status

```bash
az network firewall show --resource-group rg-hub --name azfw-hub --query "provisioningState"
# Expected: "Succeeded"
```

### Get Firewall IPs

```bash
# Private IP
az network firewall show --resource-group rg-hub --name azfw-hub --query "ipConfigurations[0].privateIpAddress"

# Public IP
az network public-ip show --resource-group rg-hub --name pip-azfw-hub --query "ipAddress"
```

### Check VPN Gateway

```bash
az network vnet-gateway show --resource-group rg-hub --name vgw-hub --query "provisioningState"
# Expected: "Succeeded"
```

---

**Remember:** This is the HUB. Spokes connect to this hub via VNet peering and route internet traffic through the firewall.
