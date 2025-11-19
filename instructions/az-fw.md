# Azure Firewall for Outbound Connectivity - Replacing NAT Gateway

## Overview

This document provides comprehensive instructions for configuring Azure Firewall to handle outbound internet traffic from spoke VNets in a hub-and-spoke topology, replacing NAT Gateway functionality.

### Architecture Overview

**Traffic Flow:**
```
Spoke Subnet VMs → Route Table (UDR) → Azure Firewall (Hub) → Internet
                                            ↓
                                    Public IP (SNAT)
```

**Key Differences from NAT Gateway:**

| Aspect | NAT Gateway | Azure Firewall |
|--------|-------------|----------------|
| Routing | Automatic, no UDR needed | Requires UDRs on spoke subnets |
| Configuration | Attach to subnet | Dedicated subnet + route tables |
| Filtering | None (outbound only) | Full stateful inspection + rules |
| SNAT Ports | 64,512 per IP | 2,496 per IP per backend instance |
| Cost | Pay per hour + data | Pay per hour + data (higher cost) |
| Management | Minimal | Requires policy management |

### Prerequisites

- Hub VNet with a subnet named **exactly** `AzureFirewallSubnet` (minimum /26, recommended /25)
- Spoke VNet(s) with subnets containing your workloads
- VNet peering configured between hub and spokes with:
  - "Allow forwarded traffic" enabled
  - "Allow gateway transit" enabled on hub (if using VPN/ExpressRoute)
- Terraform with azurerm provider version 3.117.1

## Required Components

1. **Azure Firewall** - Network security service with stateful firewall capabilities
2. **Firewall Policy** - Defines rules (network/application/NAT rules)
3. **Public IP Address** - Standard SKU for Azure Firewall's outbound SNAT
4. **Route Tables** - User Defined Routes (UDRs) to direct spoke traffic to firewall
5. **AzureFirewallSubnet** - Dedicated /26 subnet in hub VNet

## Terraform Provider Configuration

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 3.117.1"  # Exact version constraint
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}
```

## Resource Dependencies & Deployment Order

⚠️ **CRITICAL**: Resources must be created in this order:

```
1. Public IP Address (Standard SKU, Static)
2. Firewall Policy
3. Firewall Policy Rule Collection Group (optional, can be added later)
4. Azure Firewall (references Public IP + Policy)
5. Route Table (references Firewall's private IP)
6. Route Table Association (to spoke subnets)
```

## Step-by-Step Implementation

### Step 1: Public IP Address for Azure Firewall

```hcl
resource "azurerm_public_ip" "firewall_pip" {
  name                = "pip-azfw-hub"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  
  # Optional: Availability Zones for 99.99% SLA
  zones = ["1", "2", "3"]
  
  tags = var.tags
}
```

**Critical Requirements:**
- `sku` MUST be `"Standard"` (Basic SKU does not work with Azure Firewall)
- `allocation_method` MUST be `"Static"`
- If using zones, Azure Firewall must also specify the same zones

**Output for Reference:**
```hcl
output "firewall_public_ip" {
  value       = azurerm_public_ip.firewall_pip.ip_address
  description = "Public IP address used for outbound SNAT by Azure Firewall"
}
```

### Step 2: Firewall Policy

```hcl
resource "azurerm_firewall_policy" "hub_fw_policy" {
  name                = "fwpol-hub"
  resource_group_name = var.resource_group_name
  location            = var.location
  
  # SKU Options: "Basic", "Standard", "Premium"
  # Standard = basic threat intelligence, most common choice
  # Premium = IDPS, TLS inspection, URL filtering
  sku = "Standard"
  
  # Optional: DNS proxy configuration
  dns {
    proxy_enabled = true  # Allows FQDN filtering in network rules
    servers       = []    # Empty = use Azure DNS
  }
  
  # Optional: Threat Intelligence
  # "Off" = disabled
  # "Alert" = log threats but don't block
  # "Deny" = block malicious traffic
  threat_intelligence_mode = "Alert"
  
  tags = var.tags
}
```

**Key Considerations:**
- **SKU Selection**: Choose based on security requirements
  - `"Standard"`: Sufficient for most use cases, includes threat intelligence
  - `"Premium"`: Required for IDPS, TLS inspection, web categories
  - `"Basic"`: Limited features, lower cost
- **DNS Proxy**: Enable if you need FQDN-based filtering in network rules
- **Threat Intelligence**: Set to "Alert" initially, then "Deny" after testing

### Step 3: Firewall Policy Rule Collection Group

This defines the actual firewall rules. Start with permissive rules and tighten as needed.

```hcl
resource "azurerm_firewall_policy_rule_collection_group" "network_rules" {
  name               = "DefaultNetworkRuleCollectionGroup"
  firewall_policy_id = azurerm_firewall_policy.hub_fw_policy.id
  priority           = 100  # Lower number = higher priority (100-65000)
  
  # Network Rules - Process before Application Rules
  network_rule_collection {
    name     = "AllowOutbound"
    priority = 100
    action   = "Allow"
    
    rule {
      name              = "AllowInternetHTTPSHTTP"
      protocols         = ["TCP"]
      source_addresses  = ["10.0.0.0/8"]  # Adjust to your spoke address spaces
      destination_addresses = ["*"]        # Or use Service Tags like "Internet"
      destination_ports = ["80", "443"]
    }
    
    rule {
      name              = "AllowDNS"
      protocols         = ["UDP"]
      source_addresses  = ["10.0.0.0/8"]
      destination_addresses = ["*"]
      destination_ports = ["53"]
    }
    
    # Example: Using Service Tags
    rule {
      name              = "AllowAzureServices"
      protocols         = ["TCP"]
      source_addresses  = ["10.0.0.0/8"]
      destination_addresses = ["AzureCloud"]  # Service Tag
      destination_ports = ["443"]
    }
  }
  
  # Optional: Application Rules for FQDN filtering
  application_rule_collection {
    name     = "AllowWebTraffic"
    priority = 200
    action   = "Allow"
    
    rule {
      name             = "AllowMicrosoft"
      source_addresses = ["10.0.0.0/8"]
      
      protocols {
        type = "Https"
        port = 443
      }
      
      protocols {
        type = "Http"
        port = 80
      }
      
      destination_fqdns = [
        "*.microsoft.com",
        "*.windows.net",
        "*.azure.com"
      ]
    }
    
    rule {
      name             = "AllowAllHTTPS"
      source_addresses = ["10.0.0.0/8"]
      
      protocols {
        type = "Https"
        port = 443
      }
      
      destination_fqdns = ["*"]
    }
  }
}
```

**Rule Processing Order:**
1. Network rules are processed first
2. Then application rules
3. If no match, traffic is denied by default (implicit deny)
4. Priority within collection: lower number = higher priority

**Best Practices:**
- Start permissive (allow *), then restrict based on logs
- Use Service Tags when possible (e.g., "AzureCloud", "Storage", "Sql")
- Application rules are more resource-intensive than network rules
- Group similar rules into collections for easier management

**Common Service Tags:**
- `Internet` - All internet addresses
- `AzureCloud` - All Azure public IP addresses
- `Storage` - Azure Storage service
- `Sql` - Azure SQL Database
- `AzureMonitor` - Azure Monitor and Log Analytics

### Step 4: Azure Firewall

```hcl
resource "azurerm_firewall" "hub_firewall" {
  name                = "azfw-hub"
  location            = var.location
  resource_group_name = var.resource_group_name
  
  # SKU Configuration
  sku_name = "AZFW_VNet"   # For traditional VNet deployment (not vWAN)
  sku_tier = "Standard"     # MUST match firewall policy SKU
  
  # Link to Firewall Policy
  firewall_policy_id = azurerm_firewall_policy.hub_fw_policy.id
  
  # IP Configuration - Attaches to AzureFirewallSubnet
  ip_configuration {
    name                 = "azfw-ipconfig"
    subnet_id            = azurerm_subnet.firewall_subnet.id
    public_ip_address_id = azurerm_public_ip.firewall_pip.id
  }
  
  # Optional: Availability Zones (must match Public IP zones)
  zones = ["1", "2", "3"]  # 99.99% SLA with zones
  
  tags = var.tags
}
```

**Critical Requirements:**

⚠️ **Subnet Requirements:**
- Subnet MUST be named exactly `"AzureFirewallSubnet"` (case-sensitive)
- Minimum size: /26 (64 addresses)
- Recommended size: /25 or larger for production
- Cannot have a route table associated with it
- Cannot have a NAT Gateway associated (unless you want NAT Gateway + Firewall combo)

⚠️ **SKU Requirements:**
- `sku_name` = `"AZFW_VNet"` for traditional VNet deployment
- Use `"AZFW_Hub"` only for Virtual WAN deployments
- `sku_tier` MUST match the firewall_policy SKU exactly

⚠️ **Availability Zones:**
- If Public IP has zones, Firewall must specify the same zones
- Zone-redundant = 99.99% SLA vs 99.95% without zones
- Once deployed, cannot change zone configuration

**Deployment Time:**
- Expect 5-10 minutes for initial provisioning
- Firewall must reach `provisioningState: "Succeeded"` before use

**Output for Routing:**
```hcl
output "firewall_private_ip" {
  value       = azurerm_firewall.hub_firewall.ip_configuration[0].private_ip_address
  description = "Private IP address of Azure Firewall for routing configuration"
}
```

**Example AzureFirewallSubnet (if not already created):**
```hcl
resource "azurerm_subnet" "firewall_subnet" {
  name                 = "AzureFirewallSubnet"  # MUST be this exact name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub_vnet.name
  address_prefixes     = ["10.0.1.0/26"]  # Adjust to your hub VNet addressing
}
```

### Step 5: Route Table for Spoke Subnets

This is where the "magic" happens - directing spoke traffic through the firewall.

```hcl
resource "azurerm_route_table" "spoke_rt" {
  name                = "rt-spoke-to-firewall"
  location            = var.location
  resource_group_name = var.resource_group_name
  
  # BGP Route Propagation
  # Set to true if using ExpressRoute or VPN Gateway to prevent route conflicts
  # Set to false if no hybrid connectivity
  disable_bgp_route_propagation = false
  
  tags = var.tags
}

resource "azurerm_route" "default_route_to_fw" {
  name                   = "default-via-firewall"
  resource_group_name    = var.resource_group_name
  route_table_name       = azurerm_route_table.spoke_rt.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.hub_firewall.ip_configuration[0].private_ip_address
}

# Associate route table with spoke subnet(s)
resource "azurerm_subnet_route_table_association" "spoke_subnet_rt" {
  subnet_id      = var.spoke_subnet_id  # Your spoke subnet ID
  route_table_id = azurerm_route_table.spoke_rt.id
}
```

**Critical Configuration:**

⚠️ **Next Hop Configuration:**
- `next_hop_type` MUST be `"VirtualAppliance"` (not "Internet" or "VnetLocal")
- `next_hop_in_ip_address` is the firewall's **private IP**, not public IP
- The private IP is typically the 4th usable address in AzureFirewallSubnet
  - Example: If subnet is 10.0.1.0/26, firewall IP is usually 10.0.1.4

⚠️ **Association Rules:**
- Associate this route table with **spoke subnets only**
- **NEVER** associate with AzureFirewallSubnet
- **NEVER** associate with GatewaySubnet (if you have VPN/ER)
- **NEVER** associate with AzureBastionSubnet

**For Multiple Spoke Subnets:**
```hcl
# Using for_each to handle multiple spokes
resource "azurerm_route_table" "spoke_rts" {
  for_each = var.spoke_subnets  # Map of spoke subnet names to IDs
  
  name                          = "rt-${each.key}-to-firewall"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  disable_bgp_route_propagation = false
  
  tags = var.tags
}

resource "azurerm_route" "default_routes" {
  for_each = var.spoke_subnets
  
  name                   = "default-via-firewall"
  resource_group_name    = var.resource_group_name
  route_table_name       = azurerm_route_table.spoke_rts[each.key].name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.hub_firewall.ip_configuration[0].private_ip_address
}

resource "azurerm_subnet_route_table_association" "spoke_associations" {
  for_each = var.spoke_subnets
  
  subnet_id      = each.value
  route_table_id = azurerm_route_table.spoke_rts[each.key].id
}
```

**Variable Definition Example:**
```hcl
variable "spoke_subnets" {
  description = "Map of spoke subnet names to subnet IDs"
  type        = map(string)
  default = {
    "spoke1-workload" = "/subscriptions/.../subnets/workload-subnet"
    "spoke2-workload" = "/subscriptions/.../subnets/workload-subnet"
  }
}
```

### Step 6: VNet Peering Configuration

Ensure your VNet peering is configured correctly for traffic forwarding.

```hcl
# Hub to Spoke Peering
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                      = "hub-to-spoke1"
  resource_group_name       = var.hub_rg_name
  virtual_network_name      = var.hub_vnet_name
  remote_virtual_network_id = var.spoke_vnet_id
  
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true   # REQUIRED: Allows spoke to send traffic through hub
  allow_gateway_transit        = true   # Required if using VPN/ExpressRoute
  use_remote_gateways          = false
}

# Spoke to Hub Peering
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "spoke1-to-hub"
  resource_group_name       = var.spoke_rg_name
  virtual_network_name      = var.spoke_vnet_name
  remote_virtual_network_id = var.hub_vnet_id
  
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true   # REQUIRED: Allows spoke to receive forwarded traffic
  allow_gateway_transit        = false
  use_remote_gateways          = true   # Set true if hub has VPN/ExpressRoute
}
```

**Peering Requirements for Firewall Routing:**
- Both peerings must have `allow_forwarded_traffic = true`
- Hub peering needs `allow_gateway_transit = true` if using hybrid connectivity
- Spoke peering needs `use_remote_gateways = true` if hub has VPN/ER Gateway

## Complete Example: Full Configuration

```hcl
# Variables
variable "location" {
  default = "eastus"
}

variable "resource_group_name" {
  default = "rg-hub-networking"
}

variable "hub_vnet_name" {
  default = "vnet-hub"
}

variable "spoke_subnet_ids" {
  type = map(string)
  default = {
    "spoke1" = "/subscriptions/.../spoke1-subnet"
    "spoke2" = "/subscriptions/.../spoke2-subnet"
  }
}

variable "tags" {
  type = map(string)
  default = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Purpose     = "Hub-Firewall"
  }
}

# Data source for existing hub VNet
data "azurerm_virtual_network" "hub" {
  name                = var.hub_vnet_name
  resource_group_name = var.resource_group_name
}

# Data source for AzureFirewallSubnet
data "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  virtual_network_name = var.hub_vnet_name
  resource_group_name  = var.resource_group_name
}

# 1. Public IP
resource "azurerm_public_ip" "firewall" {
  name                = "pip-azfw-hub"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = var.tags
}

# 2. Firewall Policy
resource "azurerm_firewall_policy" "main" {
  name                     = "fwpol-hub"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  sku                      = "Standard"
  threat_intelligence_mode = "Alert"
  
  dns {
    proxy_enabled = true
  }
  
  tags = var.tags
}

# 3. Firewall Rules
resource "azurerm_firewall_policy_rule_collection_group" "main" {
  name               = "rcg-default-rules"
  firewall_policy_id = azurerm_firewall_policy.main.id
  priority           = 100
  
  network_rule_collection {
    name     = "allow-outbound-internet"
    priority = 100
    action   = "Allow"
    
    rule {
      name                  = "allow-http-https"
      protocols             = ["TCP"]
      source_addresses      = ["10.0.0.0/8"]
      destination_addresses = ["*"]
      destination_ports     = ["80", "443"]
    }
    
    rule {
      name                  = "allow-dns"
      protocols             = ["UDP"]
      source_addresses      = ["10.0.0.0/8"]
      destination_addresses = ["*"]
      destination_ports     = ["53"]
    }
  }
  
  application_rule_collection {
    name     = "allow-web-fqdns"
    priority = 200
    action   = "Allow"
    
    rule {
      name             = "allow-all-https"
      source_addresses = ["10.0.0.0/8"]
      
      protocols {
        type = "Https"
        port = 443
      }
      
      destination_fqdns = ["*"]
    }
  }
}

# 4. Azure Firewall
resource "azurerm_firewall" "main" {
  name                = "azfw-hub"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  firewall_policy_id  = azurerm_firewall_policy.main.id
  zones               = ["1", "2", "3"]
  
  ip_configuration {
    name                 = "ipconfig1"
    subnet_id            = data.azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }
  
  tags = var.tags
}

# 5. Route Tables for Spokes
resource "azurerm_route_table" "spokes" {
  for_each                      = var.spoke_subnet_ids
  name                          = "rt-${each.key}-to-firewall"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  disable_bgp_route_propagation = false
  tags                          = var.tags
}

resource "azurerm_route" "default_to_firewall" {
  for_each               = var.spoke_subnet_ids
  name                   = "default-via-firewall"
  resource_group_name    = var.resource_group_name
  route_table_name       = azurerm_route_table.spokes[each.key].name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.main.ip_configuration[0].private_ip_address
}

# 6. Associate Route Tables with Spoke Subnets
resource "azurerm_subnet_route_table_association" "spokes" {
  for_each       = var.spoke_subnet_ids
  subnet_id      = each.value
  route_table_id = azurerm_route_table.spokes[each.key].id
}

# Outputs
output "firewall_public_ip" {
  value       = azurerm_public_ip.firewall.ip_address
  description = "Public IP address used for outbound SNAT"
}

output "firewall_private_ip" {
  value       = azurerm_firewall.main.ip_configuration[0].private_ip_address
  description = "Private IP address of Azure Firewall"
}

output "firewall_name" {
  value       = azurerm_firewall.main.name
  description = "Name of the Azure Firewall resource"
}
```

## Verification and Testing

### Step 1: Verify Firewall Deployment

```bash
# Check firewall provisioning state
az network firewall show \
  --resource-group rg-hub-networking \
  --name azfw-hub \
  --query "provisioningState" -o tsv
# Expected output: "Succeeded"

# Get firewall private IP
az network firewall show \
  --resource-group rg-hub-networking \
  --name azfw-hub \
  --query "ipConfigurations[0].privateIpAddress" -o tsv

# Get firewall public IP
az network public-ip show \
  --resource-group rg-hub-networking \
  --name pip-azfw-hub \
  --query "ipAddress" -o tsv
```

### Step 2: Verify Effective Routes

Check that spoke subnet VMs have the correct routing:

```bash
# Get effective routes for a spoke VM's NIC
az network nic show-effective-route-table \
  --resource-group rg-spoke1 \
  --name nic-vm-spoke1 \
  -o table

# Expected output should show:
# Source    Address Prefix    Next Hop Type        Next Hop IP
# User      0.0.0.0/0         VirtualAppliance     10.0.1.4 (firewall IP)
```

**Healthy Route Table Output:**
```
Source    State    Address Prefix    Next Hop Type        Next Hop IP
--------  -------  ----------------  -------------------  -------------
Default   Active   10.1.0.0/16       VnetLocal            
User      Active   0.0.0.0/0         VirtualAppliance     10.0.1.4
Default   Active   10.0.0.0/16       VNetPeering          
```

### Step 3: Test Outbound Connectivity

From a VM in a spoke subnet:

```bash
# Test outbound connectivity
curl https://ifconfig.me
# Should return the Azure Firewall's public IP, not the VM's

# Test DNS resolution (if DNS proxy is enabled)
nslookup microsoft.com

# Test specific HTTPS connectivity
curl -I https://www.microsoft.com

# Check that you can't reach blocked sites (if you added deny rules)
curl -I https://example-blocked-site.com
```

### Step 4: Review Firewall Logs

Enable diagnostic logging to see traffic flowing through the firewall:

```hcl
# Add to your Terraform configuration
resource "azurerm_monitor_diagnostic_setting" "firewall" {
  name                       = "diag-firewall-logs"
  target_resource_id         = azurerm_firewall.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id  # Your Log Analytics workspace
  
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
```

**Query Firewall Logs in Log Analytics:**

```kusto
// Application Rule Logs
AzureDiagnostics
| where Category == "AzureFirewallApplicationRule"
| where TimeGenerated > ago(1h)
| project TimeGenerated, msg_s, SourceIP = split(split(msg_s, " ")[2], ":")[0], DestinationURL = split(msg_s, "to ")[1], Action = split(msg_s, ". ")[1]
| order by TimeGenerated desc

// Network Rule Logs
AzureDiagnostics
| where Category == "AzureFirewallNetworkRule"
| where TimeGenerated > ago(1h)
| project TimeGenerated, msg_s, SourceIP = split(split(msg_s, " ")[2], ":")[0], DestinationIP = split(split(msg_s, " ")[4], ":")[0], Action = split(msg_s, ". ")[1]
| order by TimeGenerated desc
```

## Troubleshooting Guide

### Issue: Spoke VMs Cannot Reach Internet

**Symptoms:**
- Timeouts when trying to access external resources
- `curl` commands hang or fail
- No response from external IPs

**Troubleshooting Steps:**

1. **Check Firewall Status:**
   ```bash
   az network firewall show -g rg-hub-networking -n azfw-hub --query "provisioningState"
   ```
   Should be "Succeeded"

2. **Verify Effective Routes:**
   ```bash
   az network nic show-effective-route-table -g rg-spoke1 -n nic-vm-spoke1 -o table
   ```
   Confirm 0.0.0.0/0 routes to VirtualAppliance with firewall's private IP

3. **Check Firewall Rules:**
   - Ensure network rule collection allows traffic from spoke subnets
   - Verify source addresses in rules match spoke subnet ranges
   - Check that destination addresses/ports are allowed

4. **Verify VNet Peering:**
   ```bash
   az network vnet peering show -g rg-hub -n hub-to-spoke1 --vnet-name vnet-hub
   ```
   Confirm `allowForwardedTraffic: true`

5. **Check NSGs:**
   - Ensure no NSG on spoke subnet is blocking outbound traffic
   - Verify no NSG on AzureFirewallSubnet (should have none)

6. **Review Firewall Logs:**
   - Check if requests are reaching the firewall but being denied
   - Look for "Deny" actions in logs

### Issue: Firewall Deployment Fails

**Common Causes and Solutions:**

| Error Message | Cause | Solution |
|---------------|-------|----------|
| "Subnet with name 'AzureFirewallSubnet' not found" | Subnet not named correctly | Rename subnet to exactly "AzureFirewallSubnet" |
| "Subnet too small" | Subnet is smaller than /26 | Expand subnet to /26 or larger |
| "Public IP SKU mismatch" | Public IP is not Standard SKU | Change Public IP to Standard SKU |
| "SKU tier mismatch" | Firewall SKU doesn't match policy | Ensure both use same SKU (Standard/Premium) |
| "Route table attached to subnet" | Route table on AzureFirewallSubnet | Remove route table from firewall subnet |

**General Debugging:**
```bash
# Check deployment status
az deployment group show \
  --resource-group rg-hub-networking \
  --name <deployment-name> \
  --query "properties.error"
```

### Issue: Asymmetric Routing

**Symptoms:**
- Traffic works one direction but not the other
- Connections timeout even though firewall allows them
- Intermittent connectivity issues

**Causes:**
- Route table incorrectly applied to AzureFirewallSubnet
- Missing return path through firewall
- NSG blocking return traffic

**Solutions:**
1. Remove any route tables from AzureFirewallSubnet
2. Ensure VNet peering has `allowForwardedTraffic = true` in both directions
3. Check NSGs on spoke subnets allow responses from internet
4. Verify no conflicting routes in spoke route tables

### Issue: High Latency or Performance Problems

**Causes:**
- Insufficient SNAT ports (firewall overload)
- Too many active connections
- Firewall not scaled properly

**Solutions:**
1. **Add NAT Gateway to AzureFirewallSubnet** for additional SNAT capacity:
   ```hcl
   resource "azurerm_nat_gateway" "firewall" {
     name                = "nat-firewall-outbound"
     location            = var.location
     resource_group_name = var.resource_group_name
     sku_name            = "Standard"
   }
   
   resource "azurerm_subnet_nat_gateway_association" "firewall" {
     subnet_id      = data.azurerm_subnet.firewall.id
     nat_gateway_id = azurerm_nat_gateway.firewall.id
   }
   ```

2. **Monitor SNAT port usage:**
   ```kusto
   AzureMetrics
   | where ResourceProvider == "MICROSOFT.NETWORK"
   | where MetricName == "SNATPortUtilization"
   | summarize avg(Average), max(Maximum) by bin(TimeGenerated, 5m)
   ```

3. **Optimize firewall rules:**
   - Use network rules instead of application rules where possible
   - Consolidate rules to reduce rule count
   - Use IP groups for better performance

### Issue: Cannot Access Specific Services

**Symptoms:**
- General internet works, but specific Azure services fail
- Some websites work, others don't
- API calls to specific endpoints timeout

**Troubleshooting:**

1. **Check Service Tags:**
   - Some Azure services require specific service tags
   - Add network rules with appropriate service tags:
   ```hcl
   rule {
     name                  = "allow-azure-storage"
     protocols             = ["TCP"]
     source_addresses      = ["10.0.0.0/8"]
     destination_addresses = ["Storage"]  # Service Tag
     destination_ports     = ["443"]
   }
   ```

2. **DNS Resolution Issues:**
   - Enable DNS proxy on firewall if using FQDN rules
   - Update spoke VMs to use firewall as DNS:
   ```bash
   # On Linux VM
   sudo nano /etc/resolv.conf
   nameserver 10.0.1.4  # Firewall private IP
   ```

3. **Review Application Rules:**
   - Verify FQDN patterns match your requirements
   - Check protocol types (HTTP vs HTTPS)
   - Ensure destination_fqdns includes necessary wildcards

## Security Best Practices

### 1. Principle of Least Privilege

Start with deny-all and explicitly allow only what's needed:

```hcl
# Example: Restrictive rules
network_rule_collection {
  name     = "allow-specific-services"
  priority = 100
  action   = "Allow"
  
  rule {
    name                  = "allow-https-only"
    protocols             = ["TCP"]
    source_addresses      = ["10.1.0.0/24"]  # Specific spoke subnet
    destination_addresses = ["AzureCloud"]    # Only Azure services
    destination_ports     = ["443"]           # HTTPS only
  }
}
```

### 2. Use FQDN Filtering

Prefer application rules over network rules when filtering web traffic:

```hcl
application_rule_collection {
  name     = "allow-specific-sites"
  priority = 100
  action   = "Allow"
  
  rule {
    name             = "allow-approved-sites"
    source_addresses = ["10.0.0.0/8"]
    
    protocols {
      type = "Https"
      port = 443
    }
    
    destination_fqdns = [
      "*.github.com",
      "*.docker.io",
      "*.ubuntu.com",
      "*.microsoft.com"
    ]
  }
}
```

### 3. Enable Threat Intelligence

Configure threat intelligence in "Deny" mode for production:

```hcl
resource "azurerm_firewall_policy" "main" {
  name                     = "fwpol-hub"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  sku                      = "Standard"
  threat_intelligence_mode = "Deny"  # Blocks known malicious IPs/domains
  
  threat_intelligence_allowlist {
    fqdns        = []  # Explicitly allowed FQDNs
    ip_addresses = []  # Explicitly allowed IPs
  }
}
```

### 4. Implement Logging and Monitoring

```hcl
resource "azurerm_monitor_diagnostic_setting" "firewall" {
  name                       = "diag-firewall"
  target_resource_id         = azurerm_firewall.main.id
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
  
  enabled_log {
    category = "AzureFirewallThreatIntel"
  }
  
  metric {
    category = "AllMetrics"
  }
}

# Alert on denied connections
resource "azurerm_monitor_scheduled_query_rules_alert" "denied_connections" {
  name                = "alert-firewall-denied-connections"
  location            = var.location
  resource_group_name = var.resource_group_name
  
  data_source_id = var.log_analytics_workspace_id
  description    = "Alert when firewall denies connections"
  enabled        = true
  
  query = <<-QUERY
    AzureDiagnostics
    | where Category in ("AzureFirewallApplicationRule", "AzureFirewallNetworkRule")
    | where msg_s contains "Deny"
    | summarize count() by bin(TimeGenerated, 5m)
    | where count_ > 10
  QUERY
  
  severity    = 2
  frequency   = 5
  time_window = 10
  
  action {
    action_group = [var.action_group_id]
  }
  
  trigger {
    operator  = "GreaterThan"
    threshold = 0
  }
}
```

### 5. Regular Rule Reviews

Document a process for reviewing firewall rules:

1. **Monthly Review**: Analyze logs to identify unused rules
2. **Quarterly Audit**: Review all rules for continued necessity
3. **Change Management**: Document all rule changes
4. **Emergency Access**: Have a process for temporary rule additions

### 6. Use IP Groups for Manageability

```hcl
resource "azurerm_ip_group" "spoke_subnets" {
  name                = "ipg-spoke-subnets"
  location            = var.location
  resource_group_name = var.resource_group_name
  
  cidrs = [
    "10.1.0.0/16",
    "10.2.0.0/16",
    "10.3.0.0/16"
  ]
}

# Use in rules
rule {
  name          = "allow-internet"
  protocols     = ["TCP"]
  source_ip_groups = [azurerm_ip_group.spoke_subnets.id]
  destination_addresses = ["*"]
  destination_ports = ["443"]
}
```

## Cost Optimization

### Understanding Azure Firewall Costs

Azure Firewall charges are based on:
1. **Deployment Hours**: Charged per hour firewall is deployed (~$1.25/hour for Standard)
2. **Data Processed**: Charged per GB processed (~$0.016/GB)
3. **Public IPs**: Additional IPs beyond the first (~$0.004/hour each)

**Typical Monthly Cost Example:**
- Standard Firewall (Zone-Redundant): ~$912/month
- 10 TB data processed: ~$160/month
- **Total**: ~$1,072/month

### Cost Comparison: Firewall vs NAT Gateway

| Component | NAT Gateway | Azure Firewall (Standard) |
|-----------|-------------|---------------------------|
| Base Cost | ~$32.85/month | ~$912/month |
| Data Processed (10 TB) | ~$450/month | ~$160/month |
| **Total (10 TB)** | **~$483/month** | **~$1,072/month** |
| Security Features | None | Full stateful firewall |
| SNAT Ports | 64,512 per IP | 2,496 per IP per instance |

### Optimization Strategies

#### 1. Combine NAT Gateway + Firewall

If you need high SNAT capacity and security:

```hcl
# NAT Gateway attached to AzureFirewallSubnet
resource "azurerm_nat_gateway" "firewall_nat" {
  name                = "nat-firewall"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "Standard"
}

resource "azurerm_public_ip" "nat_gateway" {
  name                = "pip-nat-firewall"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_nat_gateway_public_ip_association" "firewall" {
  nat_gateway_id       = azurerm_nat_gateway.firewall_nat.id
  public_ip_address_id = azurerm_public_ip.nat_gateway.id
}

resource "azurerm_subnet_nat_gateway_association" "firewall" {
  subnet_id      = data.azurerm_subnet.firewall.id
  nat_gateway_id = azurerm_nat_gateway.firewall_nat.id
}
```

**Benefits:**
- NAT Gateway provides SNAT ports (64K per IP)
- Firewall provides security inspection
- Lower overall cost than scaling firewall with many IPs

#### 2. Use Basic SKU for Non-Production

```hcl
resource "azurerm_firewall_policy" "dev" {
  name                = "fwpol-dev"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Basic"  # Lower cost for dev/test
}
```

#### 3. Right-Size Your Deployment

- Don't use zones in dev/test (~30% cost savings)
- Use single region for non-production
- Consider shared firewall across multiple workloads

#### 4. Monitor and Optimize Data Processing

```kusto
// Query to identify top data consumers
AzureDiagnostics
| where Category in ("AzureFirewallApplicationRule", "AzureFirewallNetworkRule")
| extend SourceIP = split(split(msg_s, " ")[2], ":")[0]
| summarize TotalDataGB = sum(todouble(split(msg_s, " bytes ")[1])) / 1073741824 by SourceIP
| order by TotalDataGB desc
| take 20
```

## Advanced Scenarios

### Scenario 1: Multiple Hub Regions

For multi-region deployments:

```hcl
module "firewall_eastus" {
  source = "./modules/azure-firewall"
  
  location            = "eastus"
  resource_group_name = "rg-hub-eastus"
  hub_vnet_name       = "vnet-hub-eastus"
  spoke_subnet_ids    = var.eastus_spoke_subnets
}

module "firewall_westus" {
  source = "./modules/azure-firewall"
  
  location            = "westus"
  resource_group_name = "rg-hub-westus"
  hub_vnet_name       = "vnet-hub-westus"
  spoke_subnet_ids    = var.westus_spoke_subnets
}
```

### Scenario 2: Forced Tunneling (ExpressRoute/VPN)

If you have on-premises connectivity and want to inspect all traffic:

```hcl
# Management IP configuration for forced tunneling
resource "azurerm_public_ip" "firewall_mgmt" {
  name                = "pip-azfw-management"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_subnet" "firewall_management" {
  name                 = "AzureFirewallManagementSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.hub_vnet_name
  address_prefixes     = ["10.0.2.0/26"]
}

resource "azurerm_firewall" "forced_tunnel" {
  name                = "azfw-hub-forced-tunnel"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  firewall_policy_id  = azurerm_firewall_policy.main.id
  
  ip_configuration {
    name                 = "primary-ipconfig"
    subnet_id            = data.azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }
  
  management_ip_configuration {
    name                 = "management-ipconfig"
    subnet_id            = azurerm_subnet.firewall_management.id
    public_ip_address_id = azurerm_public_ip.firewall_mgmt.id
  }
}
```

### Scenario 3: Integration with Azure Private DNS

```hcl
resource "azurerm_firewall_policy" "main" {
  name                = "fwpol-hub"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Standard"
  
  dns {
    proxy_enabled = true
    servers = [
      "10.0.0.4",  # Custom DNS servers
      "10.0.0.5"
    ]
  }
}

# Update spoke VNet DNS settings
resource "azurerm_virtual_network_dns_servers" "spoke" {
  virtual_network_id = var.spoke_vnet_id
  dns_servers = [
    azurerm_firewall.main.ip_configuration[0].private_ip_address
  ]
}
```

### Scenario 4: Web Application Firewall + Azure Firewall

Layer security with both:

```
Internet → Application Gateway (WAF) → Azure Firewall → Backend VMs
         (Layer 7 Protection)          (Layer 3-4 Protection)
```

## Migration Checklist

When migrating from NAT Gateway to Azure Firewall:

- [ ] Document existing NAT Gateway configuration
- [ ] Identify all spoke subnets using NAT Gateway
- [ ] Design firewall rule collections
- [ ] Create AzureFirewallSubnet in hub VNet (/26 minimum)
- [ ] Deploy Public IP (Standard, Static)
- [ ] Deploy Firewall Policy with initial permissive rules
- [ ] Deploy Azure Firewall
- [ ] Verify firewall reaches "Succeeded" state
- [ ] Create route tables with firewall as next hop
- [ ] Test in non-production environment first
- [ ] During maintenance window:
  - [ ] Associate route tables with spoke subnets
  - [ ] Remove NAT Gateway associations (or keep for SNAT boost)
  - [ ] Verify outbound connectivity
  - [ ] Monitor firewall logs for denied traffic
- [ ] Gradually tighten firewall rules
- [ ] Enable threat intelligence in "Deny" mode
- [ ] Set up monitoring and alerting
- [ ] Document configuration
- [ ] Remove old NAT Gateway (if not using for SNAT boost)

## Useful Azure CLI Commands

```bash
# Firewall Management
az network firewall list -o table
az network firewall show -g <rg> -n <name>
az network firewall list-fqdn-tags

# Policy Management
az network firewall policy list -o table
az network firewall policy rule-collection-group list --policy-name <policy> -g <rg>

# Check firewall health
az network firewall show -g <rg> -n <name> --query "{State:provisioningState, IP:ipConfigurations[0].privateIpAddress}"

# Update firewall policy
az network firewall update -g <rg> -n <name> --firewall-policy <policy-id>

# View firewall logs (requires Log Analytics)
az monitor log-analytics query -w <workspace-id> --analytics-query "
  AzureDiagnostics 
  | where Category == 'AzureFirewallNetworkRule' 
  | take 50
"

# Export firewall configuration
az network firewall show -g <rg> -n <name> > firewall-config.json

# Check route tables
az network route-table route list --route-table-name <rt-name> -g <rg> -o table

# Verify effective routes
az network nic show-effective-route-table -g <rg> -n <nic-name> -o table

# Check VNet peering
az network vnet peering list --vnet-name <vnet> -g <rg> -o table
```

## Additional Resources

### Microsoft Documentation
- [Azure Firewall Documentation](https://learn.microsoft.com/en-us/azure/firewall/)
- [Azure Firewall Policy Overview](https://learn.microsoft.com/en-us/azure/firewall/policy-rule-sets)
- [Hub-and-Spoke Topology](https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/hybrid-networking/hub-spoke)
- [Terraform AzureRM Provider 3.117.1](https://registry.terraform.io/providers/hashicorp/azurerm/3.117.1/docs)

### Terraform Registry (v3.117.1)
- [azurerm_firewall](https://registry.terraform.io/providers/hashicorp/azurerm/3.117.1/docs/resources/firewall)
- [azurerm_firewall_policy](https://registry.terraform.io/providers/hashicorp/azurerm/3.117.1/docs/resources/firewall_policy)
- [azurerm_firewall_policy_rule_collection_group](https://registry.terraform.io/providers/hashicorp/azurerm/3.117.1/docs/resources/firewall_policy_rule_collection_group)
- [azurerm_public_ip](https://registry.terraform.io/providers/hashicorp/azurerm/3.117.1/docs/resources/public_ip)
- [azurerm_route_table](https://registry.terraform.io/providers/hashicorp/azurerm/3.117.1/docs/resources/route_table)

### Architecture Examples
- [Integrate NAT Gateway with Azure Firewall](https://learn.microsoft.com/en-us/azure/firewall/integrate-with-nat-gateway)
- [Hub-spoke network topology in Azure](https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/hybrid-networking/hub-spoke?tabs=cli)

## Support and Feedback

If you encounter issues or have questions:
1. Review the troubleshooting section above
2. Check Azure Firewall logs in Log Analytics
3. Verify all prerequisites are met
4. Open an issue in your repository with:
   - Error messages
   - Terraform plan/apply output
   - Relevant Azure CLI command outputs
   - Firewall configuration details

---

**Document Version:** 1.0  
**Last Updated:** November 2024  
**Terraform Provider Version:** hashicorp/azurerm 3.117.1  
**Tested On:** Azure Commercial Cloud
