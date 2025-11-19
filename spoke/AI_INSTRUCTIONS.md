# AI Assistant Instructions for Spoke Network Module

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

**Why this matters:** This code is designed for and tested with azurerm provider 3.117.1 specifically. This must match the hub module's provider version.

## Spoke Architecture Overview

This is a **SPOKE** network in a hub-and-spoke topology:

```
SPOKE VNet → VNet Peering → Hub VNet → Azure Firewall → Internet
```

### With VPN Gateway in Hub

```
P2S Clients → VPN Gateway (Hub) → SPOKE VNet
                  ↓
            Azure Firewall → Internet
```

### Spoke Components

1. **Spoke VNet** - Workload network (e.g., 10.1.0.0/16)
2. **Subnets** - Workload subnets
3. **VNet Peering** - Two peerings (spoke-to-hub and hub-to-spoke)
4. **Route Table** - Routes internet traffic to hub's firewall
5. **Routes** - Default route (0.0.0.0/0 → firewall)

## Prerequisites

**Hub MUST be deployed first!**

Required from hub module outputs:
- `hub_vnet_id` - Hub VNet resource ID
- `hub_vnet_name` - Hub VNet name
- `hub_resource_group_name` - Hub resource group
- `firewall_private_ip` - Azure Firewall private IP
- `has_vpn_gateway` - Whether hub has VPN Gateway

## Address Space Planning

**CRITICAL:** Spoke VNet address space must NOT overlap with:
- Hub VNet (e.g., 10.0.0.0/16)
- Other spoke VNets
- P2S VPN client pool (if hub has VPN Gateway, e.g., 172.16.0.0/24)

Example allocation:
```
Hub:    10.0.0.0/16
Spoke1: 10.1.0.0/16  ← This spoke
Spoke2: 10.2.0.0/16  ← Another spoke
Spoke3: 10.3.0.0/16  ← Another spoke
P2S:    172.16.0.0/24  ← VPN clients (if VPN Gateway in hub)
```

## VNet Peering Configuration

### CRITICAL Settings

**Spoke to Hub Peering:**
```hcl
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true   # REQUIRED for firewall routing
  allow_gateway_transit        = false
  use_remote_gateways          = var.hub_has_vpn_gateway  # TRUE if hub has VPN Gateway
}
```

**Hub to Spoke Peering:**
```hcl
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true   # REQUIRED for firewall routing
  allow_gateway_transit        = var.hub_has_vpn_gateway  # TRUE if hub has VPN Gateway
  use_remote_gateways          = false
}
```

### Why These Settings Matter

1. **allow_forwarded_traffic = true** - REQUIRED on BOTH peerings for firewall routing to work
2. **use_remote_gateways** - If hub has VPN Gateway, spoke MUST set this to true to allow P2S clients to access spoke
3. **allow_gateway_transit** - If hub has VPN Gateway, hub peering MUST set this to true

## Route Table Configuration

### Standard Configuration

```hcl
resource "azurerm_route_table" "spoke" {
  name                          = "rt-spoke-to-firewall"
  disable_bgp_route_propagation = var.hub_has_vpn_gateway  # CRITICAL!
}

resource "azurerm_route" "default_to_firewall" {
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"  # MUST be VirtualAppliance
  next_hop_in_ip_address = var.firewall_private_ip
}
```

### BGP Route Propagation - CRITICAL

**If hub has VPN Gateway:**
```hcl
disable_bgp_route_propagation = true  # MUST be true
```

**Why:** VPN Gateway propagates routes via BGP. If BGP propagation is enabled, these routes will conflict with the UDR (0.0.0.0/0 → firewall), causing asymmetric routing and connection failures.

**Symptoms of wrong setting:**
- Intermittent connectivity
- Connection timeouts
- Some traffic works, some doesn't

## Subnet Configuration

### Subnet with Route Table

```hcl
spoke_subnets = {
  "workload" = {
    address_prefix        = "10.1.0.0/24"
    associate_route_table = true  # Internet via firewall
  }
}
```

### Subnet without Route Table

```hcl
spoke_subnets = {
  "privatelink" = {
    address_prefix        = "10.1.2.0/24"
    associate_route_table = false  # No firewall routing
  }
}
```

**Use cases for no route table:**
- Private Link subnets (access PaaS services privately)
- Subnets that only need hub/spoke connectivity
- Subnets with Azure services that manage their own routing

## Traffic Flow Patterns

### Pattern 1: Spoke VM to Internet

```
VM (10.1.0.10)
    ↓
Subnet Route Table: 0.0.0.0/0 → 10.0.1.4 (firewall)
    ↓
VNet Peering (allow_forwarded_traffic = true)
    ↓
Azure Firewall (10.0.1.4)
    ↓
Firewall Public IP
    ↓
Internet
```

### Pattern 2: Spoke VM to Hub VM

```
VM (10.1.0.10)
    ↓
VNet Peering (VNetLocal route)
    ↓
Hub VM (10.0.0.10)
```

No firewall involved for spoke-to-hub traffic (unless firewall rules require it).

### Pattern 3: P2S VPN Client to Spoke VM

```
P2S Client (172.16.0.10)
    ↓
VPN Gateway (Hub GatewaySubnet)
    ↓
VNet Peering (use_remote_gateways = true)
    ↓
Spoke VM (10.1.0.10)
```

**Requires:**
- Spoke peering: `use_remote_gateways = true`
- Hub peering: `allow_gateway_transit = true`

## Automatic Configuration via Locals

The spoke module auto-configures based on `hub_has_vpn_gateway`:

```hcl
locals {
  # Auto-configure based on VPN Gateway presence
  use_remote_gateways = var.hub_has_vpn_gateway  # TRUE if hub has VPN
  disable_bgp         = var.hub_has_vpn_gateway  # TRUE if hub has VPN
}
```

This ensures correct settings even if you forget to set them manually.

## Common Mistakes to Avoid

### Mistake 1: Wrong next_hop_type

```hcl
# WRONG
next_hop_type = "Internet"

# CORRECT
next_hop_type = "VirtualAppliance"
```

### Mistake 2: Missing allow_forwarded_traffic

```hcl
# WRONG - Firewall routing won't work
allow_forwarded_traffic = false

# CORRECT
allow_forwarded_traffic = true  # On BOTH peerings
```

### Mistake 3: Wrong BGP propagation setting

```hcl
# WRONG if hub has VPN Gateway
disable_bgp_route_propagation = false  # Causes route conflicts

# CORRECT if hub has VPN Gateway
disable_bgp_route_propagation = true
```

### Mistake 4: Overlapping address spaces

```hcl
# WRONG
hub_vnet_address_space  = ["10.0.0.0/16"]
spoke_vnet_address_space = ["10.0.0.0/16"]  # OVERLAPS!

# CORRECT
hub_vnet_address_space  = ["10.0.0.0/16"]
spoke_vnet_address_space = ["10.1.0.0/16"]  # Different range
```

### Mistake 5: Not setting use_remote_gateways

```hcl
# WRONG if hub has VPN Gateway
use_remote_gateways = false  # P2S clients can't reach spoke

# CORRECT if hub has VPN Gateway
use_remote_gateways = true
```

## Required Variables from Hub

Get these from hub output:

```bash
cd ../hub
terraform output -json spoke_integration_info
```

Required values:
```hcl
hub_vnet_id             = "<from output: hub_vnet_id>"
hub_vnet_name           = "<from output: hub_vnet_name>"
hub_resource_group_name = "<from output: resource_group_name>"
firewall_private_ip     = "<from output: firewall_private_ip>"
hub_has_vpn_gateway     = <from output: has_vpn_gateway>
```

## Example Configurations

### Spoke WITHOUT VPN Gateway in Hub

```hcl
hub_has_vpn_gateway           = false
peering_use_remote_gateways   = null  # Will be false
disable_bgp_route_propagation = null  # Will be false
```

### Spoke WITH VPN Gateway in Hub

```hcl
hub_has_vpn_gateway           = true
peering_use_remote_gateways   = null  # Will be true
disable_bgp_route_propagation = null  # Will be true
```

## Verification Commands

### Check VNet Peering

```bash
az network vnet peering show \
  --resource-group rg-spoke1 \
  --vnet-name vnet-spoke1 \
  --name vnet-spoke1-to-vnet-hub \
  --query "{State:peeringState, UseRemoteGateways:useRemoteGateways, AllowForwarded:allowForwardedTraffic}"
```

Expected:
```json
{
  "State": "Connected",
  "UseRemoteGateways": true,  # if hub has VPN Gateway
  "AllowForwarded": true
}
```

### Check Effective Routes

```bash
# Get VM NIC name
az vm show -g rg-spoke1 -n vm-spoke1 --query "networkProfile.networkInterfaces[0].id" -o tsv | xargs basename

# Check effective routes
az network nic show-effective-route-table \
  --resource-group rg-spoke1 \
  --name <nic-name> \
  -o table
```

Expected routes:
```
Source    Address Prefix    Next Hop Type        Next Hop IP
--------  ----------------  -------------------  -------------
User      0.0.0.0/0         VirtualAppliance     10.0.1.4
Default   10.1.0.0/16       VnetLocal
Default   10.0.0.0/16       VNetPeering
```

**Should NOT see BGP routes** if hub has VPN Gateway (because `disable_bgp_route_propagation = true`).

### Test Connectivity

```bash
# From spoke VM
curl https://ifconfig.me  # Should return firewall's public IP

ping 10.0.1.4  # Hub firewall (may be blocked by rules)

# If VPN Gateway exists
ping 172.16.0.10  # P2S client (from spoke, may be blocked)
```

## Multiple Spokes

Each spoke is independent:

```
Hub (10.0.0.0/16)
  ├── Spoke1 (10.1.0.0/16) ← This module instance
  ├── Spoke2 (10.2.0.0/16) ← Another instance
  └── Spoke3 (10.3.0.0/16) ← Another instance
```

Deploy by copying spoke folder:
```bash
cp -r spoke spoke2
cd spoke2
# Update terraform.tfvars with different address space
```

## Troubleshooting

### Issue: Can't reach internet

**Check:**
1. VNet peering state is "Connected"
2. `allow_forwarded_traffic = true` on BOTH peerings
3. Route table has 0.0.0.0/0 → firewall IP
4. Firewall rules allow spoke subnet range
5. No NSG blocking outbound

### Issue: Asymmetric routing

**Symptom:** Timeouts, intermittent connectivity

**Cause:** BGP routes conflicting with UDR

**Fix:**
```hcl
disable_bgp_route_propagation = true  # If hub has VPN Gateway
```

### Issue: P2S clients can't reach spoke

**Check:**
1. `hub_has_vpn_gateway = true`
2. Spoke peering: `use_remote_gateways = true`
3. Hub peering: `allow_gateway_transit = true`
4. Firewall allows P2S client pool (172.16.0.0/24)

## Example Code Patterns

### Complete Peering Setup

```hcl
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "${var.spoke_vnet_name}-to-${var.hub_vnet_name}"
  resource_group_name          = local.resource_group_name
  virtual_network_name         = azurerm_virtual_network.spoke.name
  remote_virtual_network_id    = var.hub_vnet_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = var.hub_has_vpn_gateway
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                         = "${var.hub_vnet_name}-to-${var.spoke_vnet_name}"
  resource_group_name          = var.hub_resource_group_name
  virtual_network_name         = var.hub_vnet_name
  remote_virtual_network_id    = azurerm_virtual_network.spoke.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = var.hub_has_vpn_gateway
  use_remote_gateways          = false
}
```

### Route Table with Conditional BGP

```hcl
resource "azurerm_route_table" "spoke" {
  name                          = "rt-spoke-to-firewall"
  location                      = var.location
  resource_group_name           = local.resource_group_name
  disable_bgp_route_propagation = var.hub_has_vpn_gateway  # Auto-configured
}
```

---

**Remember:** This is a SPOKE. It connects to the HUB via VNet peering and routes internet traffic through the hub's firewall. The hub must be deployed first.
