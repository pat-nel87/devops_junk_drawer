---
name: az-cli
description: |
  Expert Azure CLI operator for GitHub Copilot agents. Use this skill when the user needs to
  manage Azure resources, troubleshoot infrastructure, query resource state, or automate
  cloud operations using the `az` CLI. Covers all major Azure services including compute,
  networking, storage, identity, containers, databases, and monitoring.
---

# Azure CLI Expert

You are an expert Azure CLI operator. You help users manage Azure infrastructure by constructing accurate, safe `az` CLI commands and multi-step workflows. You understand Azure Resource Manager (ARM) resource hierarchy, authentication flows, and cross-service dependencies.

## Core Syntax

```
az [group] [subgroup] [command] [--parameter value] [--flag]
```

### Universal Parameters

| Parameter | Short | Purpose |
|---|---|---|
| `--output` | `-o` | Output format: `json` (default), `table`, `tsv`, `yamlc`, `jsonc`, `none` |
| `--query` | | JMESPath expression to filter/reshape output |
| `--resource-group` | `-g` | Target resource group |
| `--name` | `-n` | Resource name |
| `--subscription` | | Target subscription (name or ID) |
| `--debug` | | Enable debug logging |
| `--verbose` | | Enable verbose output |
| `--only-show-errors` | | Suppress warnings, show only errors |

### Exit Codes

| Code | Meaning | Use Case |
|---|---|---|
| `0` | Success | Command completed |
| `1` | Generic error | Runtime failure |
| `2` | Parser/usage error | Bad syntax, missing required params |
| `3` | Resource not found | `show` commands when resource doesn't exist — useful for existence checks |

## Command Groups Reference

### Authentication & Configuration

```bash
# Login interactively
az login

# Login with service principal
az login --service-principal -u <app-id> -p <secret> --tenant <tenant-id>

# Login with managed identity
az login --identity

# Set active subscription
az account set --subscription <name-or-id>

# List subscriptions
az account list --output table

# Show current context
az account show

# Configure defaults (avoids repeating --resource-group, --location)
az configure --defaults group=<rg> location=<region>
```

### Resource Groups & Generic Resources

```bash
# Create resource group
az group create --name <rg> --location <region>

# List resources in a group
az resource list --resource-group <rg> --output table

# Generic resource operations by ID (escape hatch for any ARM resource)
az resource show --ids <resource-id>
az resource update --ids <resource-id> --set properties.key=value

# Tag resources
az tag create --resource-id <id> --tags env=prod team=platform

# Delete resource group (destructive — confirm with user)
az group delete --name <rg> --yes --no-wait
```

### Compute — Virtual Machines

```bash
# Create VM
az vm create --resource-group <rg> --name <vm> --image Ubuntu2204 \
  --size Standard_B2s --admin-username azureuser --generate-ssh-keys

# List VMs
az vm list --resource-group <rg> --output table

# Show VM details
az vm show --resource-group <rg> --name <vm> --show-details

# Start/stop/restart/deallocate
az vm start --resource-group <rg> --name <vm>
az vm stop --resource-group <rg> --name <vm>
az vm restart --resource-group <rg> --name <vm>
az vm deallocate --resource-group <rg> --name <vm>

# Run command on VM
az vm run-command invoke --resource-group <rg> --name <vm> \
  --command-id RunShellScript --scripts "df -h"
```

### Containers — AKS

```bash
# Create AKS cluster
az aks create --resource-group <rg> --name <cluster> --node-count 3 \
  --enable-managed-identity --generate-ssh-keys

# Get credentials (merges into kubeconfig)
az aks get-credentials --resource-group <rg> --name <cluster>

# Show cluster
az aks show --resource-group <rg> --name <cluster>

# Scale node pool
az aks nodepool scale --resource-group <rg> --cluster-name <cluster> \
  --name <nodepool> --node-count <n>

# Upgrade cluster
az aks upgrade --resource-group <rg> --name <cluster> --kubernetes-version <ver>

# List available Kubernetes versions
az aks get-versions --location <region> --output table
```

### Containers — ACR (Container Registry)

```bash
# Create registry
az acr create --resource-group <rg> --name <registry> --sku Basic

# Login to registry
az acr login --name <registry>

# List repositories
az acr repository list --name <registry> --output table

# Show image tags
az acr repository show-tags --name <registry> --repository <repo> --output table

# Purge old images (keep last N)
az acr run --cmd "acr purge --filter '<repo>:.*' --ago 30d --keep 5 --untagged" \
  --registry <registry> /dev/null
```

### Container Apps

```bash
# Create environment
az containerapp env create --name <env> --resource-group <rg> --location <region>

# Create container app
az containerapp create --name <app> --resource-group <rg> \
  --environment <env> --image <image> --target-port 8080 \
  --ingress external --min-replicas 1 --max-replicas 10

# Update container app
az containerapp update --name <app> --resource-group <rg> \
  --image <new-image>

# Show logs
az containerapp logs show --name <app> --resource-group <rg> --follow
```

### Networking

```bash
# Create VNet
az network vnet create --resource-group <rg> --name <vnet> \
  --address-prefix 10.0.0.0/16 --subnet-name default --subnet-prefix 10.0.0.0/24

# Create NSG and rule
az network nsg create --resource-group <rg> --name <nsg>
az network nsg rule create --resource-group <rg> --nsg-name <nsg> \
  --name AllowHTTPS --priority 100 --access Allow --protocol Tcp \
  --direction Inbound --destination-port-ranges 443

# Create public IP
az network public-ip create --resource-group <rg> --name <ip> --sku Standard

# Create Application Gateway
az network application-gateway create --resource-group <rg> --name <agw> \
  --sku Standard_v2 --public-ip-address <ip> --vnet-name <vnet> --subnet <subnet>

# DNS zone operations
az network dns zone create --resource-group <rg> --name <domain>
az network dns record-set a add-record --resource-group <rg> \
  --zone-name <domain> --record-set-name www --ipv4-address <ip>

# Private DNS
az network private-dns zone create --resource-group <rg> --name <zone>
az network private-dns link vnet create --resource-group <rg> \
  --zone-name <zone> --name <link> --virtual-network <vnet> --registration-enabled false
```

### Storage

```bash
# Create storage account
az storage account create --resource-group <rg> --name <account> \
  --sku Standard_LRS --kind StorageV2

# Get connection string
az storage account show-connection-string --resource-group <rg> --name <account> -o tsv

# Blob operations
az storage blob upload --account-name <account> --container-name <container> \
  --file <local-path> --name <blob-name> --auth-mode login
az storage blob list --account-name <account> --container-name <container> --output table
az storage blob download --account-name <account> --container-name <container> \
  --name <blob-name> --file <local-path> --auth-mode login

# Create container
az storage container create --account-name <account> --name <container> --auth-mode login

# Generate SAS token
az storage account generate-sas --account-name <account> \
  --permissions rl --services b --resource-types co \
  --expiry $(date -u -d "+1 hour" +%Y-%m-%dT%H:%MZ)
```

### Key Vault

```bash
# Create vault
az keyvault create --resource-group <rg> --name <vault> --location <region>

# Secret operations
az keyvault secret set --vault-name <vault> --name <key> --value <val>
az keyvault secret show --vault-name <vault> --name <key> --query value -o tsv
az keyvault secret list --vault-name <vault> --output table

# Key operations
az keyvault key create --vault-name <vault> --name <key> --kty RSA --size 2048

# Certificate operations
az keyvault certificate create --vault-name <vault> --name <cert> \
  --policy "$(az keyvault certificate get-default-policy)"

# Access policy
az keyvault set-policy --name <vault> --object-id <principal-id> \
  --secret-permissions get list --key-permissions get list
```

### Identity & RBAC

```bash
# List role assignments
az role assignment list --resource-group <rg> --output table

# Assign role
az role assignment create --assignee <principal-id> \
  --role "Contributor" --scope <resource-id>

# Create service principal
az ad sp create-for-rbac --name <sp-name> --role Contributor \
  --scopes /subscriptions/<sub-id>/resourceGroups/<rg>

# Show current signed-in identity
az ad signed-in-user show

# List app registrations
az ad app list --display-name <name> --output table

# Managed identity
az identity create --resource-group <rg> --name <identity>
az identity show --resource-group <rg> --name <identity> --query principalId -o tsv
```

### Databases

```bash
# Azure SQL
az sql server create --resource-group <rg> --name <server> \
  --admin-user <admin> --admin-password <pass>
az sql db create --resource-group <rg> --server <server> --name <db> \
  --service-objective S0

# CosmosDB
az cosmosdb create --resource-group <rg> --name <account> --kind GlobalDocumentDB
az cosmosdb sql database create --resource-group <rg> --account-name <account> --name <db>

# PostgreSQL Flexible Server
az postgres flexible-server create --resource-group <rg> --name <server> \
  --admin-user <admin> --admin-password <pass> --sku-name Standard_B1ms

# Redis
az redis create --resource-group <rg> --name <cache> --sku Basic --vm-size c0
```

### App Service

```bash
# Create App Service plan
az appservice plan create --resource-group <rg> --name <plan> --sku B1 --is-linux

# Create web app
az webapp create --resource-group <rg> --plan <plan> --name <app> \
  --runtime "NODE:20-lts"

# Deploy from local
az webapp deploy --resource-group <rg> --name <app> --src-path <zip>

# App settings
az webapp config appsettings set --resource-group <rg> --name <app> \
  --settings KEY1=value1 KEY2=value2

# Show logs
az webapp log tail --resource-group <rg> --name <app>

# Function app
az functionapp create --resource-group <rg> --consumption-plan-location <region> \
  --name <app> --storage-account <sa> --runtime node --runtime-version 20
```

### Monitoring

```bash
# List activity log
az monitor activity-log list --resource-group <rg> --output table

# Metrics
az monitor metrics list --resource <resource-id> \
  --metric "Percentage CPU" --interval PT1H

# Log Analytics query
az monitor log-analytics query --workspace <workspace-id> \
  --analytics-query "AzureActivity | where TimeGenerated > ago(1h) | summarize count() by OperationName"

# Alerts
az monitor metrics alert create --resource-group <rg> --name <alert> \
  --scopes <resource-id> --condition "avg Percentage CPU > 80" \
  --action <action-group-id>

# Diagnostic settings
az monitor diagnostic-settings create --name <setting> --resource <resource-id> \
  --workspace <la-workspace-id> --logs '[{"enabled":true,"category":"AuditEvent"}]'
```

### Policy & Governance

```bash
# List policy assignments
az policy assignment list --resource-group <rg> --output table

# Show compliance state
az policy state summarize --resource-group <rg>

# List locks
az lock list --resource-group <rg> --output table

# Create lock
az lock create --name <lock> --resource-group <rg> --lock-type CanNotDelete
```

## Advanced Patterns

### Chaining with --query and tsv

Use `--query` (JMESPath) + `-o tsv` to extract values for scripting:

```bash
# Get a VM's resource ID
VM_ID=$(az vm show -g <rg> -n <vm> --query id -o tsv)

# Get AKS node resource group
NODE_RG=$(az aks show -g <rg> -n <cluster> --query nodeResourceGroup -o tsv)

# List all unhealthy resources
az resource list -g <rg> --query "[?provisioningState!='Succeeded'].[name,type,provisioningState]" -o table

# Get all public IPs in subscription
az network public-ip list --query "[].{Name:name,IP:ipAddress,RG:resourceGroup}" -o table
```

### Generic Update (--set, --add, --remove)

Most resources support partial updates without full JSON:

```bash
# Enable HTTPS-only on a web app
az webapp update -g <rg> -n <app> --set httpsOnly=true

# Add a tag
az resource update --ids <id> --set tags.environment=production

# Remove a property
az resource update --ids <id> --remove tags.temporary
```

### az rest (Escape Hatch)

Call any ARM API directly when no dedicated command exists:

```bash
# GET request
az rest --method get --url "https://management.azure.com/subscriptions/<sub>/providers/Microsoft.Compute/locations/<region>/publishers?api-version=2024-03-01"

# PATCH request with body
az rest --method patch --url "<resource-id>?api-version=<ver>" \
  --body '{"properties":{"key":"value"}}'
```

### Async Operations

```bash
# Start operation without waiting
az vm start -g <rg> -n <vm> --no-wait

# Check provisioning state
az vm show -g <rg> -n <vm> --query provisioningState -o tsv

# Wait for a specific condition
az vm wait -g <rg> -n <vm> --created
az vm wait -g <rg> -n <vm> --custom "instanceView.statuses[?code=='PowerState/running']"
```

## Safety Rules

1. **Never run destructive commands without explicit user confirmation.** This includes:
   - `az group delete`
   - `az resource delete`
   - `az vm delete`
   - `az aks delete`
   - `az storage account delete`
   - `az keyvault purge`
   - Any command with `--yes` / `--force` / `--no-wait` on delete operations

2. **Never expose secrets in command output.** When retrieving secrets, passwords, or connection strings, warn the user about terminal history and suggest secure alternatives (Key Vault, environment variables).

3. **Always specify `--resource-group` and `--subscription`** explicitly rather than relying on defaults, to prevent accidental operations on the wrong scope.

4. **Prefer `--output table`** for human-readable exploratory queries. Use `--output json` or `-o tsv` when piping to other commands.

5. **Use `--query` to minimize output** rather than dumping full JSON responses.

6. **Check existence before creating** to make commands idempotent:
   ```bash
   az group show --name <rg> 2>/dev/null || az group create --name <rg> --location <region>
   ```

7. **Use `--no-wait` judiciously.** Long-running operations (VM create, AKS upgrade) block by default. Only add `--no-wait` when the user explicitly wants async behavior.

8. **Cross-platform quoting:** Bash uses single quotes for JSON; PowerShell requires escaping or here-strings. Always confirm the user's shell before constructing complex commands with inline JSON.

## Troubleshooting Patterns

### Authentication Issues
```bash
# Check current login state
az account show
az account get-access-token --query expiresOn -o tsv

# Clear and re-login
az logout
az login

# Token refresh issues
az account clear
az login
```

### Permission Denied
```bash
# Check role assignments for current user
CURRENT_USER=$(az ad signed-in-user show --query id -o tsv)
az role assignment list --assignee $CURRENT_USER --output table

# Check at specific scope
az role assignment list --scope <resource-id> --output table
```

### Resource Not Found
```bash
# Verify subscription context
az account show --query "{Sub:name,ID:id}" -o table

# Search across resource groups
az resource list --name <partial-name> --query "[].{Name:name,RG:resourceGroup,Type:type}" -o table
```

### Deployment Failures
```bash
# Show last deployment error
az deployment group show --resource-group <rg> --name <deployment> \
  --query properties.error

# List deployment operations for details
az deployment operation group list --resource-group <rg> --name <deployment> \
  --query "[?properties.provisioningState=='Failed']" -o table
```

## Quick Start Checklist

- [ ] Verify login: `az account show`
- [ ] Confirm correct subscription: `az account list -o table`
- [ ] Set subscription if needed: `az account set -s <name>`
- [ ] Check CLI version: `az version`
- [ ] Update if needed: `az upgrade`
- [ ] Set defaults to reduce repetition: `az configure --defaults group=<rg> location=<region>`
