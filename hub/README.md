# Azure Hub Network with Firewall - Terraform Implementation

This Terraform configuration deploys a complete Azure hub network infrastructure with Azure Firewall for outbound internet connectivity in a hub-and-spoke topology.

**NEW:** Now includes support for Point-to-Site (P2S) VPN Gateway with Entra ID authentication! See [VPN_GATEWAY_GUIDE.md](./VPN_GATEWAY_GUIDE.md) for complete documentation.

## Architecture Overview

### Standard Hub-Spoke (No VPN)
```
Spoke VNets → VNet Peering → Hub VNet → Azure Firewall → Internet
                                           ↓
                                    Public IP (SNAT)
```

### Hub-Spoke with P2S VPN Gateway
```
P2S VPN Clients (172.16.0.0/24)
         ↓
   VPN Gateway (GatewaySubnet)
         ↓
Spoke VNets → VNet Peering → Hub VNet → Azure Firewall → Internet
                                           ↓
                                    Public IP (SNAT)
```

## Components Deployed

### Core Components (Always Deployed)
1. **Resource Group** - Container for hub networking resources
2. **Hub Virtual Network** - Central VNet in hub-and-spoke topology
3. **AzureFirewallSubnet** - Dedicated /26 subnet for Azure Firewall
4. **Azure Firewall** - Stateful firewall with outbound SNAT capability
5. **Firewall Policy** - Rule collections for network and application filtering
6. **Public IP** - Standard SKU for firewall's outbound traffic
7. **Route Table** - Default route table for spoke subnets (0.0.0.0/0 → Firewall)

### Optional Components (VPN Gateway)
8. **GatewaySubnet** - Dedicated /27 subnet for VPN Gateway (when `enable_vpn_gateway = true`)
9. **VPN Gateway** - Point-to-Site VPN with Entra ID authentication
10. **VPN Public IP(s)** - For VPN Gateway connectivity (1 or 2 for active-active)
11. **P2S Configuration** - Client address pool and authentication settings

## Prerequisites

- Azure subscription with appropriate permissions
- Terraform >= 1.0
- Azure CLI (for verification and testing)
- Azure Provider version 3.117.1 (specified in provider.tf)

## Quick Start

### 1. Clone and Configure

```bash
cd hub
cp terraform.tfvars.example terraform.tfvars
```

### 2. Customize terraform.tfvars

Edit `terraform.tfvars` with your specific values:

```hcl
location            = "eastus"
resource_group_name = "rg-hub-networking"
hub_vnet_name       = "vnet-hub"
hub_vnet_address_space = ["10.0.0.0/16"]
```

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Review the Plan

```bash
terraform plan
```

### 5. Deploy

```bash
terraform apply
```

**Expected deployment time:**
- Without VPN Gateway: 5-10 minutes (Azure Firewall provisioning)
- With VPN Gateway: 30-50 minutes (VPN Gateway takes 30-40 minutes)

### 6. Verify Deployment

After deployment, use the output commands to verify:

```bash
terraform output verification_commands
```

## Quick Start: Adding P2S VPN Gateway

To enable Point-to-Site VPN with Entra ID authentication:

```hcl
# In terraform.tfvars
enable_vpn_gateway            = true
gateway_subnet_address_prefix = "10.0.0.0/27"
p2s_client_address_pool      = ["172.16.0.0/24"]
disable_bgp_route_propagation = true  # IMPORTANT!

# VPN Gateway Settings
vpn_gateway_sku        = "VpnGw1"
vpn_auth_types         = ["AAD"]  # Entra ID
vpn_client_protocols   = ["OpenVPN"]
```

**Important when enabling VPN Gateway:**
1. Set `disable_bgp_route_propagation = true` to prevent route conflicts
2. Update spoke peerings to include `use_remote_gateways = true`
3. Include P2S client pool in `allowed_source_addresses` for firewall rules
4. Never add route tables or NSGs to GatewaySubnet

See [VPN_GATEWAY_GUIDE.md](./VPN_GATEWAY_GUIDE.md) for complete P2S VPN documentation.

## Configuration Options

### Firewall SKU Tiers

| SKU | Use Case | Features |
|-----|----------|----------|
| **Basic** | Dev/Test | Basic filtering, lower cost |
| **Standard** | Production | Threat intelligence, DNS proxy |
| **Premium** | High Security | IDPS, TLS inspection, URL filtering |

Set in `terraform.tfvars`:
```hcl
firewall_sku_tier = "Standard"
```

### Availability Zones

For **99.99% SLA** (vs 99.95%), enable zones:

```hcl
firewall_zones = ["1", "2", "3"]
```

For **cost savings** in non-production (~30% less):

```hcl
firewall_zones = []
```

### DNS Proxy

Enable for FQDN-based filtering in network rules:

```hcl
enable_dns_proxy = true
```

When enabled, spoke VMs should use the firewall's private IP as DNS server.

### Threat Intelligence

```hcl
threat_intelligence_mode = "Alert"  # Log threats
# threat_intelligence_mode = "Deny"  # Block known malicious IPs/domains
```

### Firewall Rules

#### Permissive Mode (Default)

Allow all outbound HTTPS traffic:

```hcl
allow_all_outbound_internet = true
```

#### Restrictive Mode

Allow only specific FQDNs:

```hcl
allow_all_outbound_internet = false
allowed_destination_fqdns = [
  "*.microsoft.com",
  "*.azure.com",
  "*.github.com"
]
```

### Advanced Features

#### NAT Gateway for Additional SNAT Capacity

Combine Azure Firewall with NAT Gateway for high SNAT port requirements:

```hcl
enable_nat_gateway_for_firewall = true
nat_gateway_public_ip_count     = 2  # 64K SNAT ports per IP
```

**Benefits:**
- Azure Firewall: Security inspection
- NAT Gateway: 64,512 SNAT ports per IP (vs 2,496 per firewall instance)
- Lower cost than scaling firewall with multiple IPs

#### Forced Tunneling

For hybrid scenarios (ExpressRoute/VPN) where you want all traffic to route on-premises:

```hcl
enable_forced_tunneling = true
firewall_management_subnet_address_prefix = "10.0.3.0/26"
```

Requires additional management subnet and public IP.

#### BGP Route Propagation

If using ExpressRoute or VPN Gateway:

```hcl
disable_bgp_route_propagation = true  # Prevents route conflicts
```

## Outputs

After deployment, important outputs are available:

```bash
# Firewall private IP (for spoke route tables)
terraform output firewall_private_ip

# Firewall public IP (outbound SNAT address)
terraform output firewall_public_ip

# Hub VNet ID (for spoke peering)
terraform output hub_vnet_id

# Default route table ID (for spoke subnet associations)
terraform output default_route_table_id
```

### Spoke Integration Information

Get all information needed for spoke integration:

```bash
terraform output spoke_integration_info
```

Returns:
- Hub VNet ID and name
- Firewall private IP
- Route table ID
- Resource group name
- Location
- VPN Gateway status (has_vpn_gateway)
- Gateway transit settings

## Spoke Integration

### Step 1: VNet Peering

Spoke VNets must peer with the hub and enable forwarded traffic:

```hcl
# In your spoke module
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "spoke-to-hub"
  resource_group_name       = var.spoke_rg_name
  virtual_network_name      = var.spoke_vnet_name
  remote_virtual_network_id = var.hub_vnet_id  # From hub output

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true   # REQUIRED
  use_remote_gateways          = false  # Set true if hub has VPN Gateway
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                      = "hub-to-spoke"
  resource_group_name       = var.hub_rg_name
  virtual_network_name      = var.hub_vnet_name
  remote_virtual_network_id = var.spoke_vnet_id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true   # REQUIRED
  allow_gateway_transit        = false  # Set true if hub has VPN Gateway
}
```

**IMPORTANT:** If hub has VPN Gateway (`enable_vpn_gateway = true`):
- Hub peering: Set `allow_gateway_transit = true`
- Spoke peering: Set `use_remote_gateways = true`
- This allows P2S VPN clients to access spoke resources

**Dynamic Configuration:**
```hcl
# Automatically configure based on hub output
data "terraform_remote_state" "hub" {
  backend = "azurerm"
  config = {
    # Your remote state config
  }
}

locals {
  hub_info = data.terraform_remote_state.hub.outputs.spoke_integration_info
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  # ...
  use_remote_gateways = local.hub_info.use_remote_gateways
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  # ...
  allow_gateway_transit = local.hub_info.allow_gateway_transit
}
```

### Step 2: Route Table Association

Associate the hub's route table with spoke subnets:

```hcl
# Option 1: Use the default route table created by hub module
resource "azurerm_subnet_route_table_association" "spoke" {
  subnet_id      = var.spoke_subnet_id
  route_table_id = var.hub_default_route_table_id  # From hub output
}

# Option 2: Create a new route table in spoke module
resource "azurerm_route_table" "spoke" {
  name                          = "rt-spoke-workload"
  location                      = var.location
  resource_group_name           = var.spoke_rg_name
  disable_bgp_route_propagation = true  # REQUIRED if hub has VPN Gateway
}

resource "azurerm_route" "to_firewall" {
  name                   = "default-via-firewall"
  resource_group_name    = var.spoke_rg_name
  route_table_name       = azurerm_route_table.spoke.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = var.firewall_private_ip  # From hub output
}

resource "azurerm_subnet_route_table_association" "spoke" {
  subnet_id      = var.spoke_subnet_id
  route_table_id = azurerm_route_table.spoke.id
}
```

**CRITICAL:** If hub has VPN Gateway, set `disable_bgp_route_propagation = true` to prevent VPN Gateway routes from conflicting with the firewall UDR.
```

## Verification and Testing

### 1. Check Firewall Status

```bash
az network firewall show \
  --resource-group rg-hub-networking \
  --name azfw-hub \
  --query "provisioningState" -o tsv
```

Expected: `Succeeded`

### 2. Get Firewall IPs

```bash
# Private IP
terraform output firewall_private_ip

# Public IP
terraform output firewall_public_ip
```

### 3. Verify Effective Routes

From a VM in a spoke subnet:

```bash
# Replace with your spoke VM's NIC name
az network nic show-effective-route-table \
  --resource-group rg-spoke \
  --name nic-vm-spoke \
  -o table
```

Expected output should show:
```
Source    State    Address Prefix    Next Hop Type        Next Hop IP
--------  -------  ----------------  -------------------  -------------
User      Active   0.0.0.0/0         VirtualAppliance     10.0.1.4
```

### 4. Test Outbound Connectivity

From a VM in spoke subnet:

```bash
# Should return the firewall's public IP (not the VM's)
curl https://ifconfig.me

# Test DNS resolution (if DNS proxy enabled)
nslookup microsoft.com

# Test specific HTTPS connectivity
curl -I https://www.microsoft.com
```

### 5. Review Firewall Logs

If diagnostic settings are enabled:

```kusto
// Application Rule Logs
AzureDiagnostics
| where Category == "AzureFirewallApplicationRule"
| where TimeGenerated > ago(1h)
| project TimeGenerated, msg_s
| order by TimeGenerated desc

// Network Rule Logs
AzureDiagnostics
| where Category == "AzureFirewallNetworkRule"
| where TimeGenerated > ago(1h)
| project TimeGenerated, msg_s
| order by TimeGenerated desc
```

## Cost Estimation

### Standard Firewall (Zone-Redundant)

**Monthly Costs:**
- Firewall deployment: ~$912/month (24/7 availability)
- Data processing (10 TB): ~$160/month
- Public IP (1): Included in firewall cost
- **Total**: ~$1,072/month

### Cost Optimization Tips

1. **Remove zones in non-production** (~30% savings):
   ```hcl
   firewall_zones = []
   ```

2. **Use Basic SKU for dev/test** (lower hourly rate):
   ```hcl
   firewall_sku_tier = "Basic"
   ```

3. **Add NAT Gateway for SNAT** (instead of multiple firewall IPs):
   ```hcl
   enable_nat_gateway_for_firewall = true
   ```

4. **Share firewall across multiple workloads** (instead of per-workload firewalls)

## Troubleshooting

### Issue: Spoke VMs Cannot Reach Internet

**Check:**
1. Firewall provisioning state is "Succeeded"
2. Effective routes show 0.0.0.0/0 → VirtualAppliance
3. VNet peering has `allow_forwarded_traffic = true`
4. Firewall rules allow traffic from spoke subnet ranges
5. No NSG blocking outbound traffic

### Issue: Firewall Deployment Fails

**Common causes:**
- Subnet not named exactly "AzureFirewallSubnet"
- Subnet smaller than /26
- Public IP not Standard SKU
- SKU tier mismatch between firewall and policy

### Issue: High Latency or Performance

**Solutions:**
- Enable NAT Gateway for additional SNAT capacity
- Monitor SNAT port utilization
- Optimize firewall rules (use network rules over application rules)
- Check if threat intelligence is blocking legitimate traffic

## Monitoring and Diagnostics

Enable diagnostic settings in `terraform.tfvars`:

```hcl
enable_diagnostic_settings = true
log_analytics_workspace_id = "/subscriptions/xxxxx/.../workspaces/xxxxx"
```

This enables logging for:
- Application rules (FQDN filtering)
- Network rules (IP-based filtering)
- DNS proxy queries
- Threat intelligence alerts

## Security Best Practices

1. **Start Permissive, Then Restrict**
   - Deploy with `allow_all_outbound_internet = true`
   - Monitor logs to understand traffic patterns
   - Gradually tighten rules

2. **Enable Threat Intelligence**
   ```hcl
   threat_intelligence_mode = "Deny"  # In production
   ```

3. **Use FQDN Filtering**
   - Prefer application rules over network rules for web traffic
   - Provides better visibility and control

4. **Regular Rule Reviews**
   - Monthly: Review logs for denied traffic
   - Quarterly: Audit all rules for necessity
   - Document all rule changes

5. **Implement Monitoring**
   - Enable diagnostic settings
   - Set up alerts for denied connections
   - Monitor SNAT port utilization

## File Structure

```
hub/
├── provider.tf                  # Provider configuration (azurerm 3.117.1)
├── variables.tf                 # Input variables
├── main.tf                      # Main resource definitions
├── outputs.tf                   # Output values for spoke integration
├── terraform.tfvars.example     # Example variable values
└── README.md                    # This file
```

## Resources Created

| Resource Type | Resource Name | Purpose |
|--------------|---------------|---------|
| Resource Group | `rg-hub-networking` | Container for hub resources |
| Virtual Network | `vnet-hub` | Hub VNet |
| Subnet | `AzureFirewallSubnet` | Firewall subnet (/26) |
| Public IP | `pip-azfw-hub` | Firewall public IP (Standard/Static) |
| Firewall Policy | `fwpol-vnet-hub` | Firewall rule collections |
| Azure Firewall | `azfw-hub` | Firewall instance |
| Route Table | `rt-spoke-to-firewall` | Default route table for spokes |
| Route | `default-via-firewall` | 0.0.0.0/0 → Firewall route |

## Additional Resources

- [Azure Firewall Documentation](https://learn.microsoft.com/en-us/azure/firewall/)
- [Hub-Spoke Topology](https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/hybrid-networking/hub-spoke)
- [Terraform AzureRM 3.117.1 Docs](https://registry.terraform.io/providers/hashicorp/azurerm/3.117.1/docs)
- [Azure Firewall Pricing](https://azure.microsoft.com/en-us/pricing/details/azure-firewall/)

## Support

For issues or questions:
1. Review troubleshooting section
2. Check Azure Firewall logs
3. Verify all prerequisites are met
4. Review terraform plan output

## License

This is example code for educational purposes.

---

**Version:** 1.0
**Terraform Provider:** azurerm 3.117.1
**Last Updated:** November 2024
