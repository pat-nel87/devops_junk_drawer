# Azure Spoke Network - Terraform Implementation

This Terraform configuration deploys a spoke network that connects to the hub network with Azure Firewall. All internet-bound traffic is routed through the hub's Azure Firewall.

**IMPORTANT:** This spoke module requires the hub module to be deployed first. See `../hub/README.md` for hub deployment.

## Architecture

```
Spoke VNet (10.1.0.0/16)
    ↓
VNet Peering
    ↓
Hub VNet (10.0.0.0/16)
    ↓
Azure Firewall (10.0.1.4)
    ↓
Internet (SNAT)
```

### With VPN Gateway in Hub

```
P2S VPN Clients (172.16.0.0/24)
    ↓
VPN Gateway ←→ Spoke VNet (10.1.0.0/16)
    ↓               ↓
    VNet Peering ←──┘
    ↓
Azure Firewall (10.0.1.4)
    ↓
Internet (SNAT)
```

## Prerequisites

1. **Hub deployed first** - The hub module must be deployed and outputs available
2. **Hub outputs** - You need values from hub's `spoke_integration_info` output
3. **Azure Provider 3.117.1** - EXACT version (specified in provider.tf)
4. **Non-overlapping address space** - Spoke VNet must not overlap with hub or other spokes

## Quick Start

### Step 1: Get Hub Information

```bash
cd ../hub
terraform output -json spoke_integration_info > ../spoke/hub-info.json
cd ../spoke
```

The hub output provides:
- `hub_vnet_id` - Hub VNet resource ID
- `hub_vnet_name` - Hub VNet name
- `firewall_private_ip` - Azure Firewall's private IP
- `has_vpn_gateway` - Whether hub has VPN Gateway
- `resource_group_name` - Hub resource group name

### Step 2: Configure Spoke

```bash
cp terraform.tfvars.example terraform.tfvars
vi terraform.tfvars
```

Minimum required configuration:

```hcl
# Basic settings
location              = "eastus"  # Match hub location
spoke_vnet_name       = "vnet-spoke1"
spoke_vnet_address_space = ["10.1.0.0/16"]  # Must NOT overlap

# From hub output
hub_vnet_id             = "<from hub output>"
hub_vnet_name           = "vnet-hub"
hub_resource_group_name = "rg-hub-networking"
firewall_private_ip     = "10.0.1.4"
hub_has_vpn_gateway     = false  # Set to true if hub has VPN Gateway
```

### Step 3: Deploy

```bash
terraform init
terraform plan
terraform apply
```

**Deployment time:** 1-3 minutes

### Step 4: Verify

```bash
terraform output verification_commands
```

## Configuration

### Subnet Configuration

Define workload subnets with route table association:

```hcl
spoke_subnets = {
  "workload" = {
    address_prefix        = "10.1.0.0/24"
    associate_route_table = true  # Internet via firewall
  }
  "data" = {
    address_prefix        = "10.1.1.0/24"
    associate_route_table = true
  }
  "privatelink" = {
    address_prefix        = "10.1.2.0/24"
    associate_route_table = false  # No firewall routing
  }
}
```

### VPN Gateway Integration

**CRITICAL:** If hub has VPN Gateway, configure these settings:

```hcl
hub_has_vpn_gateway           = true
peering_use_remote_gateways   = null  # Auto-configured to true
disable_bgp_route_propagation = null  # Auto-configured to true
```

**Why these settings matter:**
1. `hub_has_vpn_gateway = true` enables automatic configuration
2. `use_remote_gateways = true` allows P2S VPN clients to access spoke
3. `disable_bgp_route_propagation = true` prevents VPN BGP routes from conflicting with firewall UDR

### Route Table Options

**Option 1: Create new route table (default)**

```hcl
create_route_table = true
route_table_name   = "rt-spoke1-to-firewall"
```

**Option 2: Use hub's default route table**

```hcl
create_route_table         = false
hub_default_route_table_id = "<from hub output: default_route_table_id>"
```

## Traffic Flow

### Spoke VM to Internet

```
VM (10.1.0.10)
    ↓
Subnet route table: 0.0.0.0/0 → 10.0.1.4 (VirtualAppliance)
    ↓
VNet Peering (allow_forwarded_traffic = true)
    ↓
Azure Firewall (10.0.1.4)
    ↓
Firewall Public IP (SNAT)
    ↓
Internet
```

### P2S VPN Client to Spoke VM (if hub has VPN Gateway)

```
P2S Client (172.16.0.10)
    ↓
VPN Gateway (GatewaySubnet)
    ↓
VNet Peering (use_remote_gateways = true)
    ↓
Spoke VM (10.1.0.10)
```

## Important Configurations

### VNet Peering Settings

```hcl
# Spoke to Hub
allow_virtual_network_access = true
allow_forwarded_traffic      = true   # REQUIRED for firewall routing
use_remote_gateways          = true   # If hub has VPN Gateway

# Hub to Spoke
allow_virtual_network_access = true
allow_forwarded_traffic      = true   # REQUIRED for firewall routing
allow_gateway_transit        = true   # If hub has VPN Gateway
```

### Route Table Settings

```hcl
# CRITICAL if hub has VPN Gateway
disable_bgp_route_propagation = true

# Default route
address_prefix         = "0.0.0.0/0"
next_hop_type          = "VirtualAppliance"
next_hop_in_ip_address = "10.0.1.4"  # Firewall private IP
```

## Outputs

```bash
# Spoke VNet information
terraform output spoke_vnet_id
terraform output spoke_vnet_name

# Subnet IDs
terraform output subnet_ids

# Peering status
terraform output peering_status

# Configuration summary
terraform output spoke_configuration
```

## Verification

### Check VNet Peering

```bash
az network vnet peering show \
  --resource-group rg-spoke1-networking \
  --name vnet-spoke1-to-vnet-hub \
  --vnet-name vnet-spoke1 \
  --query "peeringState"
```

Expected: `"Connected"`

### Check Effective Routes

```bash
# Get a VM's NIC name
az vm show -g rg-spoke1-networking -n vm-spoke1 --query "networkProfile.networkInterfaces[0].id" -o tsv

# Check effective routes
az network nic show-effective-route-table \
  --resource-group rg-spoke1-networking \
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

If hub has VPN Gateway, **should NOT see** BGP-propagated routes (because `disable_bgp_route_propagation = true`).

### Test Connectivity

From a VM in the spoke:

```bash
# Should return Azure Firewall's public IP
curl https://ifconfig.me

# Test connectivity to hub
ping 10.0.1.4  # Firewall IP (may be blocked by firewall rules)

# Test DNS (if firewall DNS proxy enabled)
nslookup microsoft.com
```

## Troubleshooting

### Issue: VMs Cannot Reach Internet

**Check:**
1. VNet peering state is "Connected"
2. Route table shows 0.0.0.0/0 → firewall IP
3. Firewall rules allow spoke subnet range
4. No NSG blocking outbound traffic

**Verify:**
```bash
# Check peering
az network vnet peering show -g rg-spoke1-networking \
  --vnet-name vnet-spoke1 \
  --name vnet-spoke1-to-vnet-hub

# Check routes
az network nic show-effective-route-table -g rg-spoke1-networking -n <nic-name>

# Check NSG
az network nsg rule list -g rg-spoke1-networking --nsg-name <nsg-name> -o table
```

### Issue: Cannot Access Hub Resources

**Check:**
1. VNet peering has `allow_virtual_network_access = true`
2. No NSG blocking traffic between hub and spoke
3. Firewall allows spoke-to-hub traffic (if rules are restrictive)

### Issue: P2S VPN Clients Cannot Access Spoke

**Check:**
1. `hub_has_vpn_gateway = true`
2. Spoke peering has `use_remote_gateways = true`
3. Hub peering has `allow_gateway_transit = true`
4. Firewall allows P2S client pool (172.16.0.0/24)

**Verify:**
```bash
az network vnet peering show -g rg-spoke1-networking \
  --vnet-name vnet-spoke1 \
  --name vnet-spoke1-to-vnet-hub \
  --query "{UseRemoteGateways:useRemoteGateways, State:peeringState}"
```

### Issue: Asymmetric Routing

**Symptoms:** Connections timeout, intermittent connectivity

**Cause:** BGP routes from VPN Gateway conflicting with UDR

**Solution:**
```hcl
disable_bgp_route_propagation = true  # In route table
```

**Verify:**
```bash
az network route-table show -g rg-spoke1-networking \
  --name rt-spoke1-to-firewall \
  --query "disableBgpRoutePropagation"
# Should return: true (if hub has VPN Gateway)
```

## Multiple Spokes

Deploy additional spokes by creating new directories:

```bash
# Copy spoke template
cp -r spoke spoke2

# Update configuration
cd spoke2
vi terraform.tfvars

# Change these values:
spoke_vnet_name         = "vnet-spoke2"
spoke_vnet_address_space = ["10.2.0.0/16"]  # Different address space
resource_group_name     = "rg-spoke2-networking"
```

Each spoke is independent and connects to the same hub.

## File Structure

```
spoke/
├── provider.tf                  # Provider configuration (azurerm 3.117.1)
├── variables.tf                 # Input variables
├── main.tf                      # Main resource definitions
├── outputs.tf                   # Output values
├── terraform.tfvars.example     # Example configuration
└── README.md                    # This file
```

## Resources Created

| Resource Type | Resource Name | Purpose |
|--------------|---------------|---------|
| Resource Group | `rg-spoke1-networking` | Container for spoke resources |
| Virtual Network | `vnet-spoke1` | Spoke VNet |
| Subnets | `workload`, `data`, etc. | Spoke subnets |
| VNet Peering | `vnet-spoke1-to-vnet-hub` | Spoke to hub peering |
| VNet Peering | `vnet-hub-to-vnet-spoke1` | Hub to spoke peering |
| Route Table | `rt-spoke1-to-firewall` | Routes to firewall |
| Route | `default-via-hub-firewall` | 0.0.0.0/0 → Firewall |

## Additional Resources

- [Hub Implementation](../hub/README.md)
- [VPN Gateway Guide](../hub/VPN_GATEWAY_GUIDE.md)
- [Hub-Spoke Topology](https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/hybrid-networking/hub-spoke)
- [VNet Peering](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-network-peering-overview)

---

**Version:** 1.0
**Terraform Provider:** azurerm 3.117.1
**Last Updated:** November 2024
