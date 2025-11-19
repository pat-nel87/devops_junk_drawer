# Point-to-Site VPN Gateway with Entra ID Authentication

## Overview

This hub implementation now supports Point-to-Site (P2S) VPN Gateway with Entra ID (Azure AD) authentication, allowing remote users to securely connect to the hub and access spoke resources through the Azure Firewall.

## Architecture with VPN Gateway

```
P2S VPN Clients (172.16.0.0/24)
         ↓
   VPN Gateway (GatewaySubnet)
         ↓
   Hub VNet (10.0.0.0/16)
         ↓
   Azure Firewall → Spoke VNets
         ↓
   Internet (SNAT)
```

## Key Components Added

1. **GatewaySubnet** - Dedicated /27 subnet for VPN Gateway (exact name required)
2. **VPN Gateway** - P2S VPN with Entra ID authentication
3. **Public IP(s)** - For VPN Gateway connectivity
4. **P2S Client Address Pool** - IP addresses assigned to VPN clients (172.16.0.0/24)
5. **Entra ID Configuration** - Azure AD authentication for VPN clients

## Important Design Considerations

### 1. BGP Route Propagation

**CRITICAL:** When deploying a VPN Gateway, set `disable_bgp_route_propagation = true` on spoke route tables.

```hcl
disable_bgp_route_propagation = true
```

**Why?** VPN Gateway propagates routes via BGP. Without disabling BGP propagation on spoke route tables, these routes can conflict with the UDR (0.0.0.0/0 → Firewall), causing asymmetric routing.

### 2. VNet Peering Configuration

When VPN Gateway is present, spoke peerings **MUST** be configured differently:

```hcl
# Hub to Spoke Peering
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                      = "hub-to-spoke"
  resource_group_name       = var.hub_rg_name
  virtual_network_name      = var.hub_vnet_name
  remote_virtual_network_id = var.spoke_vnet_id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true   # REQUIRED for VPN Gateway
  use_remote_gateways          = false
}

# Spoke to Hub Peering
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "spoke-to-hub"
  resource_group_name       = var.spoke_rg_name
  virtual_network_name      = var.spoke_vnet_name
  remote_virtual_network_id = var.hub_vnet_id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = true   # REQUIRED for VPN Gateway
}
```

**Key Points:**
- Hub peering: `allow_gateway_transit = true`
- Spoke peering: `use_remote_gateways = true`
- This allows P2S clients to access spoke VNets through the gateway

### 3. Firewall Rules for P2S Clients

Ensure firewall rules allow traffic from P2S client address pool:

```hcl
allowed_source_addresses = ["10.0.0.0/8", "172.16.0.0/24"]
```

The P2S client pool (172.16.0.0/24) must be included in allowed source addresses.

### 4. Subnet Requirements

**GatewaySubnet:**
- **Must** be named exactly `GatewaySubnet` (case-sensitive)
- Minimum size: /27 (32 addresses)
- Recommended size: /26 or /25 for production
- **Never** associate a route table with GatewaySubnet
- **Never** associate an NSG with GatewaySubnet (blocks VPN traffic)

**Address Planning:**
```
Hub VNet: 10.0.0.0/16
├── GatewaySubnet: 10.0.0.0/27          # VPN Gateway
├── AzureFirewallSubnet: 10.0.1.0/26    # Azure Firewall
└── Other subnets as needed

P2S Client Pool: 172.16.0.0/24          # Must not overlap with any VNet
```

## Configuration

### Basic Configuration

```hcl
# Enable VPN Gateway
enable_vpn_gateway = true

# GatewaySubnet
gateway_subnet_address_prefix = "10.0.0.0/27"

# VPN Gateway SKU
vpn_gateway_sku        = "VpnGw1"      # VpnGw1, VpnGw2, VpnGw3
vpn_gateway_generation = "Generation1"

# P2S Client Pool (must not overlap with hub/spoke VNets)
p2s_client_address_pool = ["172.16.0.0/24"]

# Entra ID Authentication
vpn_auth_types       = ["AAD"]
vpn_client_protocols = ["OpenVPN"]
```

### Entra ID (Azure AD) Configuration

The implementation uses **Azure VPN Client App ID** by default:

```hcl
# Default values (automatically configured)
aad_tenant_id = null  # Uses current tenant
aad_audience  = "41b23e61-6c1e-4545-b367-cd054e0ed4b4"  # Azure VPN Client App ID
aad_issuer    = "https://sts.windows.net/{tenant-id}/"
```

**Custom Entra ID App (Optional):**

If you want to use a custom Azure AD application:

```hcl
aad_tenant_id = "your-tenant-id"
aad_audience  = "your-custom-app-id"
aad_issuer    = "https://sts.windows.net/your-tenant-id/"
```

### VPN Gateway SKUs

| SKU | Tunnels | Throughput | Availability Zones |
|-----|---------|------------|-------------------|
| VpnGw1 | 250 | 650 Mbps | No |
| VpnGw2 | 500 | 1 Gbps | No |
| VpnGw3 | 1000 | 1.25 Gbps | No |
| VpnGw1AZ | 250 | 650 Mbps | Yes (99.99% SLA) |
| VpnGw2AZ | 500 | 1 Gbps | Yes (99.99% SLA) |
| VpnGw3AZ | 1000 | 1.25 Gbps | Yes (99.99% SLA) |

### Active-Active Configuration

For high availability (99.99% SLA):

```hcl
enable_active_active_vpn = true
vpn_gateway_sku          = "VpnGw1AZ"  # Must use AZ SKU
vpn_gateway_zones        = ["1", "2", "3"]
```

This creates two VPN Gateway instances with two public IPs.

## Deployment

### Step 1: Update Configuration

```bash
cd hub
vim terraform.tfvars
```

Enable VPN Gateway:
```hcl
enable_vpn_gateway            = true
gateway_subnet_address_prefix = "10.0.0.0/27"
p2s_client_address_pool      = ["172.16.0.0/24"]
disable_bgp_route_propagation = true  # Important!
```

### Step 2: Deploy

```bash
terraform plan
terraform apply
```

**Expected deployment time:**
- Azure Firewall: 5-10 minutes
- VPN Gateway: 20-45 minutes (VPN Gateway takes longer)

### Step 3: Verify Deployment

```bash
# Check VPN Gateway provisioning
az network vnet-gateway show \
  --resource-group rg-hub-networking \
  --name vgw-hub \
  --query "provisioningState" -o tsv

# Get VPN Gateway public IP
terraform output vpn_gateway_public_ip

# Get Entra ID configuration
terraform output vpn_aad_configuration
```

## Client Configuration

### Download VPN Client

```bash
# Generate VPN client configuration
az network vnet-gateway vpn-client generate \
  --resource-group rg-hub-networking \
  --name vgw-hub \
  --processor-architecture Amd64
```

This returns a URL to download the VPN client configuration package.

### Configure Azure VPN Client

1. **Download Azure VPN Client**
   - Windows: Microsoft Store
   - macOS: App Store
   - Linux: [Azure VPN Client for Linux](https://aka.ms/azvpnclientdownload)

2. **Import VPN Profile**
   - Extract the downloaded configuration
   - Import `azurevpnconfig.xml` into Azure VPN Client

3. **Connect**
   - Sign in with your Entra ID credentials
   - VPN client receives IP from P2S pool (172.16.0.0/24)

### Client Routing

Once connected, P2S clients can access:
- Hub VNet resources (10.0.0.0/16)
- Spoke VNet resources (10.x.0.0/16) via VNet peering
- Internet traffic through Azure Firewall (inspected & SNAT'd)

## Traffic Flow

### P2S Client to Spoke VNet

```
P2S Client (172.16.0.10)
    ↓
VPN Gateway (GatewaySubnet)
    ↓
Hub VNet
    ↓
VNet Peering (use_remote_gateways = true)
    ↓
Spoke VNet (10.1.0.0/16)
```

### P2S Client to Internet

```
P2S Client (172.16.0.10)
    ↓
VPN Gateway (GatewaySubnet)
    ↓
Hub VNet
    ↓
Azure Firewall (AzureFirewallSubnet)
    ↓
Internet (SNAT to Firewall Public IP)
```

## Spoke Integration with VPN Gateway

### VNet Peering Updates

Spoke modules must update peering configuration:

```hcl
# Get hub integration info
data "terraform_remote_state" "hub" {
  backend = "azurerm"
  config = {
    # Your remote state config
  }
}

locals {
  has_vpn_gateway = data.terraform_remote_state.hub.outputs.spoke_integration_info.has_vpn_gateway
}

# Spoke to Hub Peering
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "spoke-to-hub"
  resource_group_name       = var.spoke_rg_name
  virtual_network_name      = var.spoke_vnet_name
  remote_virtual_network_id = var.hub_vnet_id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = local.has_vpn_gateway  # Dynamic based on hub
}
```

### Route Table Configuration

Spoke route tables should disable BGP propagation:

```hcl
resource "azurerm_route_table" "spoke" {
  name                          = "rt-spoke-workload"
  location                      = var.location
  resource_group_name           = var.spoke_rg_name
  disable_bgp_route_propagation = true  # Prevent VPN routes from conflicting
}
```

## Security Considerations

### 1. Conditional Access Policies

Configure Entra ID Conditional Access for VPN:

```
Azure AD → Security → Conditional Access → New Policy
- Cloud apps: Azure VPN (41b23e61-6c1e-4545-b367-cd054e0ed4b4)
- Conditions: Trusted locations, device compliance, MFA
- Grant: Require MFA, require compliant device
```

### 2. Firewall Rules for P2S

Ensure firewall allows P2S clients but apply appropriate restrictions:

```hcl
# Network Rule Collection
network_rule_collection {
  name     = "AllowP2SOutbound"
  priority = 100
  action   = "Allow"

  rule {
    name              = "AllowHTTPS"
    protocols         = ["TCP"]
    source_addresses  = ["172.16.0.0/24"]  # P2S pool
    destination_addresses = ["*"]
    destination_ports = ["443"]
  }
}
```

### 3. NSG Considerations

**Never** apply NSGs to:
- GatewaySubnet (breaks VPN connectivity)
- AzureFirewallSubnet (breaks firewall functionality)

Apply NSGs to spoke subnets as needed.

### 4. Monitor VPN Connections

```kusto
// VPN Gateway Logs
AzureDiagnostics
| where Category == "P2SDiagnosticLog"
| where TimeGenerated > ago(1h)
| project TimeGenerated, OperationName, Message
| order by TimeGenerated desc
```

## Troubleshooting

### Issue: P2S Clients Cannot Connect

**Check:**
1. VPN Gateway provisioning state is "Succeeded"
2. Entra ID tenant ID is correct
3. Azure VPN Client App ID is whitelisted in Azure AD
4. No NSG on GatewaySubnet
5. GatewaySubnet has no route table

**Verify:**
```bash
az network vnet-gateway show \
  --resource-group rg-hub-networking \
  --name vgw-hub \
  --query "{State: provisioningState, P2S: vpnClientConfiguration}"
```

### Issue: P2S Clients Cannot Reach Spoke VNets

**Check:**
1. Spoke peering has `use_remote_gateways = true`
2. Hub peering has `allow_gateway_transit = true`
3. Firewall rules allow P2S client pool (172.16.0.0/24)
4. No NSG blocking traffic on spoke subnets

**Test from P2S client:**
```bash
# Should work
ping 10.1.0.4  # Spoke VM

# Check effective routes
ipconfig /all  # Windows
ifconfig       # Linux/macOS
```

### Issue: Asymmetric Routing / Connection Timeouts

**Cause:** BGP routes from VPN Gateway conflicting with UDRs

**Solution:**
```hcl
disable_bgp_route_propagation = true  # On spoke route tables
```

Verify:
```bash
az network route-table show \
  --resource-group rg-spoke \
  --name rt-spoke \
  --query "disableBgpRoutePropagation"
# Should return: true
```

### Issue: P2S Clients Cannot Reach Internet

**Check:**
1. Firewall rules allow P2S client pool
2. Azure Firewall has proper outbound rules
3. No NSG blocking outbound on spoke subnets

**Verify from P2S client:**
```bash
curl https://ifconfig.me
# Should return: Azure Firewall's public IP
```

## Cost Implications

### VPN Gateway Costs

**VpnGw1 (Basic):**
- ~$140/month (24/7 deployment)
- 250 P2S connections
- 650 Mbps throughput

**VpnGw2 (Medium):**
- ~$365/month
- 500 P2S connections
- 1 Gbps throughput

**VpnGw1AZ (Zone-Redundant):**
- ~$175/month
- 99.99% SLA
- 250 P2S connections

**Total Hub Cost with VPN (Standard SKUs):**
- Azure Firewall (Standard, Zone-Redundant): ~$912/month
- VPN Gateway (VpnGw1): ~$140/month
- Data Processing: ~$0.016/GB
- **Total**: ~$1,052/month + data costs

### Cost Optimization

1. **Non-Production:** Use VpnGw1 without zones (~$140/month)
2. **Active-Active:** Only enable if 99.99% SLA required
3. **Right-Size SKU:** Start with VpnGw1, scale up if needed
4. **Scheduled Deployments:** For dev/test, delete VPN Gateway when not in use

## Deployment Timeline

```
Start
  ↓
terraform apply
  ↓
[0-5 min] Resource Group, VNet, Subnets created
  ↓
[5-15 min] Firewall Policy & Azure Firewall deploying
  ↓
[15-20 min] Azure Firewall ready (can configure spokes)
  ↓
[20-45 min] VPN Gateway deploying (parallel to firewall)
  ↓
[45-50 min] VPN Gateway ready
  ↓
Complete (Total: ~50 minutes)
```

**Pro Tip:** Azure Firewall and VPN Gateway deploy in parallel, so total time is dominated by VPN Gateway's 30-40 minute deployment.

## Additional Resources

- [Azure VPN Gateway Documentation](https://learn.microsoft.com/en-us/azure/vpn-gateway/)
- [P2S VPN with Entra ID](https://learn.microsoft.com/en-us/azure/vpn-gateway/openvpn-azure-ad-tenant)
- [Azure VPN Client Download](https://aka.ms/azvpnclientdownload)
- [VPN Gateway FAQ](https://learn.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-vpn-faq)

---

**Note:** This guide assumes familiarity with the base hub implementation. See main README.md for core hub/firewall documentation.
