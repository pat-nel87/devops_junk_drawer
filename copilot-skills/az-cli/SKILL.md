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
# Create AKS cluster with managed identity
az aks create --resource-group <rg> --name <cluster> --node-count 3 \
  --enable-managed-identity --generate-ssh-keys

# Create AKS with OIDC + workload identity (modern auth)
az aks create --resource-group <rg> --name <cluster> --node-count 3 \
  --enable-managed-identity --enable-oidc-issuer --enable-workload-identity \
  --generate-ssh-keys

# Get credentials (merges into kubeconfig)
az aks get-credentials --resource-group <rg> --name <cluster>

# Get credentials for admin (bypasses RBAC — use sparingly)
az aks get-credentials --resource-group <rg> --name <cluster> --admin

# Show cluster
az aks show --resource-group <rg> --name <cluster>

# Get OIDC issuer URL (needed for workload identity federation)
az aks show --resource-group <rg> --name <cluster> --query oidcIssuerProfile.issuerUrl -o tsv

# Get node resource group (MC_ group)
az aks show --resource-group <rg> --name <cluster> --query nodeResourceGroup -o tsv

# Node pool operations
az aks nodepool list --resource-group <rg> --cluster-name <cluster> -o table
az aks nodepool scale --resource-group <rg> --cluster-name <cluster> \
  --name <nodepool> --node-count <n>
az aks nodepool add --resource-group <rg> --cluster-name <cluster> \
  --name <pool> --node-count 3 --node-vm-size Standard_D4s_v3 --mode User
az aks nodepool upgrade --resource-group <rg> --cluster-name <cluster> \
  --name <pool> --kubernetes-version <ver>

# Upgrade cluster
az aks upgrade --resource-group <rg> --name <cluster> --kubernetes-version <ver>
az aks get-upgrades --resource-group <rg> --name <cluster> -o table

# List available Kubernetes versions
az aks get-versions --location <region> --output table

# Enable monitoring add-on
az aks enable-addons --resource-group <rg> --name <cluster> --addons monitoring \
  --workspace-resource-id <la-workspace-id>

# Enable Azure Key Vault secrets provider
az aks enable-addons --resource-group <rg> --name <cluster> \
  --addons azure-keyvault-secrets-provider

# Check cluster health and running config
az aks show --resource-group <rg> --name <cluster> \
  --query "{K8s:kubernetesVersion,Power:powerState.code,Provisioning:provisioningState,FQDN:fqdn}" -o table

# Cordon/drain via stop/start (whole cluster)
az aks stop --resource-group <rg> --name <cluster>
az aks start --resource-group <rg> --name <cluster>

# Run kubectl commands via az (when kubectl not available)
az aks command invoke --resource-group <rg> --name <cluster> \
  --command "kubectl get pods -A"
```

### AKS + ACR Integration

```bash
# Attach ACR to AKS (grants AcrPull role to kubelet identity)
az aks update --resource-group <rg> --name <cluster> --attach-acr <registry>

# Detach ACR
az aks update --resource-group <rg> --name <cluster> --detach-acr <registry>

# Verify ACR access from AKS
az aks check-acr --resource-group <rg> --name <cluster> --acr <registry>.azurecr.io

# Import image to ACR (avoids Docker Hub rate limits)
az acr import --name <registry> --source docker.io/library/nginx:latest \
  --image nginx:latest

# Build image in ACR (no local Docker needed)
az acr build --registry <registry> --image <repo>:<tag> --file Dockerfile .

# ACR task for automated builds on git push
az acr task create --registry <registry> --name <task> \
  --image <repo>:{{.Run.ID}} --context <git-url> --file Dockerfile \
  --git-access-token <pat>
```

### AKS + AGIC (Application Gateway Ingress Controller)

```bash
# Create Application Gateway for AGIC
az network public-ip create --resource-group <rg> --name <agw-pip> --sku Standard
az network application-gateway create --resource-group <rg> --name <agw> \
  --sku Standard_v2 --public-ip-address <agw-pip> \
  --vnet-name <vnet> --subnet <agw-subnet> --priority 100

# Enable AGIC add-on on AKS (greenfield — creates new AppGW)
az aks enable-addons --resource-group <rg> --name <cluster> \
  --addons ingress-appgw --appgw-name <agw> --appgw-subnet-cidr "10.225.0.0/16"

# Enable AGIC add-on (brownfield — use existing AppGW)
az aks enable-addons --resource-group <rg> --name <cluster> \
  --addons ingress-appgw --appgw-id <appgw-resource-id>

# Verify AGIC pod is running
az aks command invoke --resource-group <rg> --name <cluster> \
  --command "kubectl get pods -n kube-system -l app=ingress-appgw"

# Check AGIC identity and permissions
AGIC_IDENTITY=$(az aks show -g <rg> -n <cluster> \
  --query addonProfiles.ingressApplicationGateway.identity.clientId -o tsv)
az role assignment list --assignee $AGIC_IDENTITY -o table

# Show AppGW backend health (diagnose 502/504 issues)
az network application-gateway show-backend-health \
  --resource-group <rg> --name <agw> -o table

# Show AppGW health probes
az network application-gateway probe list --resource-group <rg> --gateway-name <agw> -o table

# Check AppGW WAF rules (if WAF enabled)
az network application-gateway waf-policy list --resource-group <rg> -o table

# View AppGW access logs (requires diagnostic settings → Log Analytics)
az monitor log-analytics query --workspace <workspace-id> --analytics-query "
AzureDiagnostics
| where ResourceType == 'APPLICATIONGATEWAYS'
| where Category == 'ApplicationGatewayAccessLog'
| project TimeGenerated, clientIP_s, httpMethod_s, requestUri_s, httpStatus_d, serverRouted_s
| order by TimeGenerated desc
| take 50
"
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

# VNet peering
az network vnet peering create --resource-group <rg-1> --vnet-name <vnet-1> \
  --name <peering-name> --remote-vnet <vnet-2-resource-id> --allow-vnet-access
az network vnet peering create --resource-group <rg-2> --vnet-name <vnet-2> \
  --name <peering-name-reverse> --remote-vnet <vnet-1-resource-id> --allow-vnet-access

# Show effective routes on a NIC (debug routing)
az network nic show-effective-route-table --resource-group <rg> --name <nic> -o table

# Show effective NSG rules on a NIC (debug connectivity)
az network nic list-effective-nsg --resource-group <rg> --name <nic>

# Network Watcher connectivity check
az network watcher test-connectivity --resource-group <rg> \
  --source-resource <vm-id> --dest-address <ip-or-fqdn> --dest-port 443

# Network Watcher IP flow verify (is traffic allowed?)
az network watcher test-ip-flow --direction Inbound --resource-group <rg> \
  --vm <vm-name> --local <vm-ip>:* --remote <source-ip>:* --protocol Tcp --port 443

# User-defined route table
az network route-table create --resource-group <rg> --name <rt>
az network route-table route create --resource-group <rg> --route-table-name <rt> \
  --name <route> --address-prefix 0.0.0.0/0 --next-hop-type VirtualAppliance \
  --next-hop-ip-address <firewall-ip>
az network vnet subnet update --resource-group <rg> --vnet-name <vnet> \
  --name <subnet> --route-table <rt>
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

### Monitoring — Log Analytics Workspaces

```bash
# Create Log Analytics workspace
az monitor log-analytics workspace create --resource-group <rg> \
  --workspace-name <workspace> --location <region> --sku PerGB2018

# Show workspace details
az monitor log-analytics workspace show --resource-group <rg> --workspace-name <workspace>

# Get workspace ID (used in KQL queries)
az monitor log-analytics workspace show --resource-group <rg> \
  --workspace-name <workspace> --query customerId -o tsv

# Get workspace resource ID (used in --workspace-resource-id params)
az monitor log-analytics workspace show --resource-group <rg> \
  --workspace-name <workspace> --query id -o tsv

# List workspaces in subscription
az monitor log-analytics workspace list --output table

# List tables in workspace
az monitor log-analytics workspace table list --resource-group <rg> \
  --workspace-name <workspace> --query "[].{Name:name,Plan:plan,Retention:retentionInDays}" -o table

# Update retention
az monitor log-analytics workspace update --resource-group <rg> \
  --workspace-name <workspace> --retention-time 90

# Check workspace usage / ingestion volume
az monitor log-analytics query --workspace <workspace-id> --analytics-query "
Usage
| where TimeGenerated > ago(30d)
| summarize TotalGB = sum(Quantity) / 1024 by DataType
| order by TotalGB desc
" -o table

# List linked solutions (Container Insights, Sentinel, etc.)
az monitor log-analytics solution list --resource-group <rg> -o table
```

### Monitoring — KQL Queries via CLI

The `az monitor log-analytics query` command runs KQL (Kusto Query Language) queries against Log Analytics workspaces. This is the most powerful diagnostic tool in the Azure CLI.

```bash
# Basic query structure
az monitor log-analytics query --workspace <workspace-id> \
  --analytics-query "<KQL>" -o table

# --- Activity & Audit ---

# Recent ARM operations (who did what)
az monitor log-analytics query --workspace <workspace-id> --analytics-query "
AzureActivity
| where TimeGenerated > ago(24h)
| where OperationNameValue !has 'read'
| project TimeGenerated, Caller, OperationNameValue, ActivityStatusValue, ResourceGroup
| order by TimeGenerated desc
| take 50
" -o table

# Failed ARM operations
az monitor log-analytics query --workspace <workspace-id> --analytics-query "
AzureActivity
| where TimeGenerated > ago(24h)
| where ActivityStatusValue == 'Failed'
| project TimeGenerated, Caller, OperationNameValue, Properties_d.statusMessage
| order by TimeGenerated desc
" -o table

# --- Container Insights (AKS) ---

# Pod failures and restarts
az monitor log-analytics query --workspace <workspace-id> --analytics-query "
KubePodInventory
| where TimeGenerated > ago(1h)
| where PodStatus in ('Failed', 'Unknown')
  or ContainerRestartCount > 3
| project TimeGenerated, Namespace, Name, PodStatus, ContainerRestartCount, ClusterName
| order by ContainerRestartCount desc
" -o table

# Container CPU usage by namespace
az monitor log-analytics query --workspace <workspace-id> --analytics-query "
Perf
| where TimeGenerated > ago(1h)
| where ObjectName == 'K8SContainer' and CounterName == 'cpuUsageNanoCores'
| summarize AvgCPU = avg(CounterValue) / 1000000 by bin(TimeGenerated, 5m), InstanceName
| order by AvgCPU desc
| take 20
" -o table

# Container memory usage
az monitor log-analytics query --workspace <workspace-id> --analytics-query "
Perf
| where TimeGenerated > ago(1h)
| where ObjectName == 'K8SContainer' and CounterName == 'memoryWorkingSetBytes'
| summarize AvgMemMB = avg(CounterValue) / 1048576 by InstanceName
| order by AvgMemMB desc
| take 20
" -o table

# Container logs (stdout/stderr) for a specific pod
az monitor log-analytics query --workspace <workspace-id> --analytics-query "
ContainerLogV2
| where TimeGenerated > ago(1h)
| where PodName has '<pod-name>'
| project TimeGenerated, PodName, ContainerName, LogMessage, LogSource
| order by TimeGenerated desc
| take 100
"

# Node conditions (NotReady, pressure)
az monitor log-analytics query --workspace <workspace-id> --analytics-query "
KubeNodeInventory
| where TimeGenerated > ago(30m)
| where Status != 'Ready'
| project TimeGenerated, Computer, Status, Labels, ClusterName
" -o table

# OOMKilled containers
az monitor log-analytics query --workspace <workspace-id> --analytics-query "
ContainerInventory
| where TimeGenerated > ago(24h)
| where ContainerState == 'Failed' and ExitCode == 137
| project TimeGenerated, ContainerID, Name, Image, ContainerState, ExitCode
| order by TimeGenerated desc
" -o table

# AKS cluster autoscaler events
az monitor log-analytics query --workspace <workspace-id> --analytics-query "
KubeEvents
| where TimeGenerated > ago(2h)
| where Source has 'cluster-autoscaler'
| project TimeGenerated, Name, Namespace, Reason, Message
| order by TimeGenerated desc
" -o table

# --- Networking & AppGW ---

# Application Gateway 4xx/5xx errors
az monitor log-analytics query --workspace <workspace-id> --analytics-query "
AzureDiagnostics
| where ResourceType == 'APPLICATIONGATEWAYS'
| where Category == 'ApplicationGatewayAccessLog'
| where httpStatus_d >= 400
| summarize Count = count() by httpStatus_d, requestUri_s, serverRouted_s
| order by Count desc
| take 20
" -o table

# AppGW backend health failures
az monitor log-analytics query --workspace <workspace-id> --analytics-query "
AzureDiagnostics
| where ResourceType == 'APPLICATIONGATEWAYS'
| where Category == 'ApplicationGatewayAccessLog'
| where httpStatus_d == 502 or httpStatus_d == 504
| summarize Count = count() by bin(TimeGenerated, 5m), serverRouted_s, requestUri_s
| order by TimeGenerated desc
" -o table

# NSG flow logs (blocked traffic)
az monitor log-analytics query --workspace <workspace-id> --analytics-query "
AzureNetworkAnalytics_CL
| where TimeGenerated > ago(1h)
| where FlowStatus_s == 'D'
| summarize Count = count() by SrcIP_s, DestIP_s, DestPort_d, NSGRule_s
| order by Count desc
| take 20
" -o table

# DNS query failures
az monitor log-analytics query --workspace <workspace-id> --analytics-query "
AzureDiagnostics
| where ResourceType == 'DNSZONES'
| where ResultCode != 'NOERROR'
| summarize Count = count() by Query_s, ResultCode, ClientIp_s
| order by Count desc
" -o table

# --- Security & Identity ---

# Failed sign-in attempts
az monitor log-analytics query --workspace <workspace-id> --analytics-query "
SigninLogs
| where TimeGenerated > ago(24h)
| where ResultType != '0'
| summarize FailureCount = count() by UserPrincipalName, ResultDescription, IPAddress, AppDisplayName
| order by FailureCount desc
| take 20
" -o table

# Risky sign-ins
az monitor log-analytics query --workspace <workspace-id> --analytics-query "
SigninLogs
| where TimeGenerated > ago(7d)
| where RiskLevelDuringSignIn in ('high', 'medium')
| project TimeGenerated, UserPrincipalName, IPAddress, Location, RiskLevelDuringSignIn, RiskDetail
| order by TimeGenerated desc
" -o table

# Key Vault access audit
az monitor log-analytics query --workspace <workspace-id> --analytics-query "
AzureDiagnostics
| where ResourceType == 'VAULTS'
| where Category == 'AuditEvent'
| project TimeGenerated, OperationName, CallerIPAddress, identity_claim_upn_s, ResultType
| order by TimeGenerated desc
| take 50
" -o table

# --- Resource Health ---

# Resource health events
az monitor log-analytics query --workspace <workspace-id> --analytics-query "
AzureActivity
| where CategoryValue == 'ResourceHealth'
| where TimeGenerated > ago(7d)
| project TimeGenerated, ResourceGroup, _ResourceId, Properties_d
| order by TimeGenerated desc
" -o table

# --- Cost / Usage ---

# Ingestion by data type (cost optimization)
az monitor log-analytics query --workspace <workspace-id> --analytics-query "
Usage
| where TimeGenerated > ago(7d)
| where IsBillable == true
| summarize BillableGB = sum(Quantity) / 1024 by DataType
| order by BillableGB desc
" -o table
```

### Monitoring — Application Insights

```bash
# Create Application Insights (workspace-based)
az monitor app-insights component create --app <app-insights> \
  --resource-group <rg> --location <region> --kind web \
  --workspace <la-workspace-resource-id>

# Show instrumentation key and connection string
az monitor app-insights component show --app <app-insights> --resource-group <rg> \
  --query "{InstrumentationKey:instrumentationKey,ConnectionString:connectionString}"

# Query App Insights traces
az monitor app-insights query --app <app-insights> --resource-group <rg> \
  --analytics-query "
traces
| where timestamp > ago(1h)
| where severityLevel >= 3
| project timestamp, message, severityLevel, operation_Name
| order by timestamp desc
| take 50
"

# Query App Insights requests (HTTP)
az monitor app-insights query --app <app-insights> --resource-group <rg> \
  --analytics-query "
requests
| where timestamp > ago(1h)
| summarize Count = count(), AvgDuration = avg(duration), FailRate = countif(success == false) * 100.0 / count()
  by name
| order by Count desc
"

# Query exceptions
az monitor app-insights query --app <app-insights> --resource-group <rg> \
  --analytics-query "
exceptions
| where timestamp > ago(24h)
| summarize Count = count() by type, outerMessage
| order by Count desc
| take 20
"

# Query dependencies (external calls — databases, APIs)
az monitor app-insights query --app <app-insights> --resource-group <rg> \
  --analytics-query "
dependencies
| where timestamp > ago(1h)
| where success == false
| summarize FailCount = count() by target, name, resultCode
| order by FailCount desc
"

# Show live metrics summary
az monitor app-insights metrics show --app <app-insights> --resource-group <rg> \
  --metric requests/count --interval PT5M --aggregation sum

# Page views and performance (browser-side)
az monitor app-insights query --app <app-insights> --resource-group <rg> \
  --analytics-query "
pageViews
| where timestamp > ago(24h)
| summarize Views = count(), AvgDuration = avg(duration) by name
| order by Views desc
"

# Custom events
az monitor app-insights query --app <app-insights> --resource-group <rg> \
  --analytics-query "
customEvents
| where timestamp > ago(24h)
| summarize Count = count() by name
| order by Count desc
"

# End-to-end transaction search (by operation ID)
az monitor app-insights query --app <app-insights> --resource-group <rg> \
  --analytics-query "
union requests, dependencies, exceptions, traces
| where operation_Id == '<operation-id>'
| project timestamp, itemType, name, message, resultCode, success, duration
| order by timestamp asc
"

# Availability test results
az monitor app-insights query --app <app-insights> --resource-group <rg> \
  --analytics-query "
availabilityResults
| where timestamp > ago(24h)
| summarize SuccessRate = countif(success == true) * 100.0 / count() by name, location
| order by SuccessRate asc
"
```

### Monitoring — Metrics

```bash
# List available metrics for a resource
az monitor metrics list-definitions --resource <resource-id> \
  --query "[].{Metric:name.value,Display:name.localizedValue,Unit:unit}" -o table

# CPU metrics for a VM (last hour, 5-minute granularity)
az monitor metrics list --resource <resource-id> \
  --metric "Percentage CPU" --interval PT5M --aggregation Average \
  --start-time $(date -u -d "-1 hour" +%Y-%m-%dT%H:%MZ) -o table

# Multiple metrics at once
az monitor metrics list --resource <resource-id> \
  --metric "Percentage CPU" "Available Memory Bytes" --interval PT5M -o table

# AKS node CPU/memory
az monitor metrics list --resource <aks-resource-id> \
  --metric "node_cpu_usage_percentage" "node_memory_working_set_percentage" \
  --interval PT5M -o table

# AKS pod count by phase
az monitor metrics list --resource <aks-resource-id> \
  --metric "kube_pod_status_phase" --interval PT5M -o table

# Application Gateway metrics
az monitor metrics list --resource <appgw-resource-id> \
  --metric "HealthyHostCount" "UnhealthyHostCount" "TotalRequests" "FailedRequests" \
  --interval PT5M -o table

# Storage account metrics
az monitor metrics list --resource <storage-resource-id> \
  --metric "Transactions" "Ingress" "Egress" --interval PT1H -o table

# Key Vault request latency
az monitor metrics list --resource <keyvault-resource-id> \
  --metric "ServiceApiLatency" "ServiceApiHit" --interval PT5M -o table

# SQL Database DTU/CPU
az monitor metrics list --resource <sqldb-resource-id> \
  --metric "dtu_consumption_percent" "cpu_percent" "storage_percent" \
  --interval PT5M -o table
```

### Monitoring — Alerts & Action Groups

```bash
# Create action group (email + webhook)
az monitor action-group create --resource-group <rg> --name <ag> \
  --short-name <short> \
  --action email admin admin@example.com \
  --action webhook ops https://hooks.example.com/alert

# Create action group with Azure Function
az monitor action-group create --resource-group <rg> --name <ag> \
  --short-name <short> \
  --action azurefunction <name> <function-app-resource-id> <function-name> <http-trigger-url>

# List action groups
az monitor action-group list --resource-group <rg> -o table

# Create metric alert (e.g. high CPU)
az monitor metrics alert create --resource-group <rg> --name <alert> \
  --scopes <resource-id> \
  --condition "avg Percentage CPU > 80" \
  --window-size 5m --evaluation-frequency 1m \
  --severity 2 \
  --action <action-group-id> \
  --description "CPU above 80% for 5 minutes"

# Create metric alert for AKS node NotReady
az monitor metrics alert create --resource-group <rg> --name aks-node-notready \
  --scopes <aks-resource-id> \
  --condition "avg kube_node_status_condition{status='true',condition='Ready'} < 1" \
  --severity 1 --action <action-group-id>

# Create log alert (KQL-based)
az monitor scheduled-query create --resource-group <rg> --name <alert> \
  --scopes <la-workspace-resource-id> \
  --condition "count > 0" \
  --condition-query "
    ContainerLogV2
    | where LogMessage has 'FATAL' or LogMessage has 'OutOfMemory'
    | where TimeGenerated > ago(5m)
  " \
  --severity 1 --action-groups <action-group-resource-id> \
  --evaluation-frequency 5m --window-size 5m

# Create activity log alert (e.g. resource deleted)
az monitor activity-log alert create --resource-group <rg> --name <alert> \
  --condition category=Administrative and operationName=Microsoft.Resources/subscriptions/resourceGroups/delete \
  --action-group <action-group-id>

# List alerts
az monitor metrics alert list --resource-group <rg> -o table
az monitor scheduled-query list --resource-group <rg> -o table

# Show alert rule details
az monitor metrics alert show --resource-group <rg> --name <alert>

# Disable/enable alert
az monitor metrics alert update --resource-group <rg> --name <alert> --enabled false
```

### Monitoring — Diagnostic Settings

Every Azure resource can forward logs and metrics to Log Analytics, Storage, or Event Hubs.

```bash
# List available diagnostic categories for a resource
az monitor diagnostic-settings categories list --resource <resource-id> \
  --query "[].{Category:name,Type:categoryType}" -o table

# Enable all logs + metrics → Log Analytics
az monitor diagnostic-settings create --name <setting> --resource <resource-id> \
  --workspace <la-workspace-id> \
  --logs '[{"categoryGroup":"allLogs","enabled":true}]' \
  --metrics '[{"category":"AllMetrics","enabled":true}]'

# Enable specific categories (e.g. Key Vault audit only)
az monitor diagnostic-settings create --name <setting> --resource <resource-id> \
  --workspace <la-workspace-id> \
  --logs '[{"category":"AuditEvent","enabled":true},{"category":"AzurePolicyEvaluationDetails","enabled":true}]'

# Enable for AKS (Container Insights + audit logs)
az monitor diagnostic-settings create --name aks-diag --resource <aks-resource-id> \
  --workspace <la-workspace-id> \
  --logs '[
    {"category":"kube-apiserver","enabled":true},
    {"category":"kube-audit","enabled":true},
    {"category":"kube-audit-admin","enabled":true},
    {"category":"kube-controller-manager","enabled":true},
    {"category":"kube-scheduler","enabled":true},
    {"category":"cluster-autoscaler","enabled":true},
    {"category":"guard","enabled":true}
  ]'

# Enable for Application Gateway
az monitor diagnostic-settings create --name appgw-diag --resource <appgw-resource-id> \
  --workspace <la-workspace-id> \
  --logs '[
    {"category":"ApplicationGatewayAccessLog","enabled":true},
    {"category":"ApplicationGatewayPerformanceLog","enabled":true},
    {"category":"ApplicationGatewayFirewallLog","enabled":true}
  ]' \
  --metrics '[{"category":"AllMetrics","enabled":true}]'

# Enable for NSG (flow logs)
az network watcher flow-log create --resource-group <rg> --name <flowlog> \
  --nsg <nsg-id> --workspace <la-workspace-id> \
  --storage-account <storage-id> --enabled true --retention 30 \
  --traffic-analytics true --traffic-analytics-interval 10

# List diagnostic settings on a resource
az monitor diagnostic-settings list --resource <resource-id> -o table

# Delete diagnostic setting
az monitor diagnostic-settings delete --name <setting> --resource <resource-id>
```

### Monitoring — Activity Log

```bash
# Recent activity in a resource group
az monitor activity-log list --resource-group <rg> \
  --start-time $(date -u -d "-24 hours" +%Y-%m-%dT%H:%MZ) \
  --query "[?status.value=='Failed'].{Time:eventTimestamp,Op:operationName.value,Status:status.value,Caller:caller}" \
  -o table

# Filter by caller (who did this?)
az monitor activity-log list --resource-group <rg> \
  --caller <upn-or-sp-id> -o table

# Filter by resource
az monitor activity-log list --resource-id <resource-id> -o table

# Subscription-level (role assignments, policy changes)
az monitor activity-log list \
  --start-time $(date -u -d "-7 days" +%Y-%m-%dT%H:%MZ) \
  --query "[?contains(operationName.value, 'roleAssignment')]" -o table
```

### Monitoring — Service Health & Resource Health

```bash
# Current service health issues
az rest --method get \
  --url "https://management.azure.com/subscriptions/<sub-id>/providers/Microsoft.ResourceHealth/events?api-version=2022-10-01&queryStartTime=$(date -u -d '-7 days' +%Y-%m-%dT%H:%MZ)" \
  --query "value[].{Title:properties.title,Impact:properties.impactType,Status:properties.status,Start:properties.impactStartTime}" -o table

# Resource health for a specific resource
az rest --method get \
  --url "<resource-id>/providers/Microsoft.ResourceHealth/availabilityStatuses/current?api-version=2023-07-01-preview" \
  --query "{Status:properties.availabilityState,Summary:properties.summary,Since:properties.occurredTime}"

# Resource health for all resources in a group
az resource list -g <rg> --query "[].id" -o tsv | while read id; do
  echo "=== $id ==="
  az rest --method get --url "$id/providers/Microsoft.ResourceHealth/availabilityStatuses/current?api-version=2023-07-01-preview" \
    --query "properties.{State:availabilityState,Summary:summary}" -o table 2>/dev/null
done
```

### FluxCD GitOps via AKS

```bash
# Install Flux extension on AKS
az k8s-extension create --resource-group <rg> --cluster-name <cluster> \
  --cluster-type managedClusters --name flux --extension-type microsoft.flux \
  --scope cluster

# Create Flux GitRepository source
az k8s-configuration flux create --resource-group <rg> --cluster-name <cluster> \
  --cluster-type managedClusters --name <config-name> \
  --url <git-repo-url> --branch <branch> \
  --scope cluster --namespace flux-system \
  --https-user <user> --https-key <pat>

# Create Flux GitRepository with SSH
az k8s-configuration flux create --resource-group <rg> --cluster-name <cluster> \
  --cluster-type managedClusters --name <config-name> \
  --url <ssh-git-url> --branch <branch> \
  --scope cluster --namespace flux-system \
  --ssh-private-key-file <key-path>

# Add kustomization to existing config
az k8s-configuration flux kustomization create --resource-group <rg> \
  --cluster-name <cluster> --cluster-type managedClusters \
  --name <kustomization-name> --flux-configuration-name <config-name> \
  --path <path-in-repo> --prune true --interval 5m \
  --depends-on <other-kustomization>

# List Flux configurations
az k8s-configuration flux list --resource-group <rg> --cluster-name <cluster> \
  --cluster-type managedClusters -o table

# Show Flux config status (compliance)
az k8s-configuration flux show --resource-group <rg> --cluster-name <cluster> \
  --cluster-type managedClusters --name <config-name> \
  --query "{Compliance:complianceState,Source:sourceKind,URL:gitRepository.url,Branch:gitRepository.repositoryRef.branch}"

# Show kustomization status
az k8s-configuration flux kustomization show --resource-group <rg> \
  --cluster-name <cluster> --cluster-type managedClusters \
  --name <kustomization-name> --flux-configuration-name <config-name>

# Force reconciliation
az k8s-configuration flux update --resource-group <rg> --cluster-name <cluster> \
  --cluster-type managedClusters --name <config-name>

# Delete Flux configuration (destructive — confirm with user)
az k8s-configuration flux delete --resource-group <rg> --cluster-name <cluster> \
  --cluster-type managedClusters --name <config-name> --yes

# List all k8s extensions (Flux, Azure Policy, etc.)
az k8s-extension list --resource-group <rg> --cluster-name <cluster> \
  --cluster-type managedClusters -o table
```

### Azure AD / Entra ID & Workload Identity

```bash
# --- Workload Identity Federation (AKS → Azure resources without secrets) ---

# 1. Create managed identity
az identity create --resource-group <rg> --name <identity>
CLIENT_ID=$(az identity show -g <rg> -n <identity> --query clientId -o tsv)
IDENTITY_ID=$(az identity show -g <rg> -n <identity> --query id -o tsv)

# 2. Get AKS OIDC issuer
OIDC_ISSUER=$(az aks show -g <rg> -n <cluster> --query oidcIssuerProfile.issuerUrl -o tsv)

# 3. Create federated credential (links K8s service account → managed identity)
az identity federated-credential create --name <fed-cred-name> \
  --resource-group <rg> --identity-name <identity> \
  --issuer $OIDC_ISSUER \
  --subject system:serviceaccount:<namespace>:<service-account-name> \
  --audiences api://AzureADTokenExchange

# 4. Assign roles to the managed identity
az role assignment create --assignee $CLIENT_ID \
  --role "Key Vault Secrets User" --scope <keyvault-resource-id>

# 5. List federated credentials
az identity federated-credential list --resource-group <rg> --identity-name <identity> -o table

# --- App Registrations ---

# Create app registration
az ad app create --display-name <app-name>
APP_ID=$(az ad app list --display-name <app-name> --query "[0].appId" -o tsv)

# Create service principal for app
az ad sp create --id $APP_ID

# Add client secret (note: prefer federated credentials for workloads)
az ad app credential reset --id $APP_ID --display-name <secret-name>

# Add API permission
az ad app permission add --id $APP_ID \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope

# Grant admin consent
az ad app permission admin-consent --id $APP_ID

# --- Groups & Membership ---

# List groups
az ad group list --display-name <filter> --query "[].{Name:displayName,ID:id}" -o table

# Show group members
az ad group member list --group <group-id> --query "[].{Name:displayName,UPN:userPrincipalName}" -o table

# Add member to group
az ad group member add --group <group-id> --member-id <user-or-sp-object-id>

# Check if user is in a group
az ad group member check --group <group-id> --member-id <object-id>
```

### Private Endpoints & Private Link

```bash
# Create private endpoint for Key Vault
az network private-endpoint create --resource-group <rg> --name <pe-name> \
  --vnet-name <vnet> --subnet <subnet> \
  --private-connection-resource-id <keyvault-resource-id> \
  --group-id vault --connection-name <connection-name>

# Create private endpoint for Storage
az network private-endpoint create --resource-group <rg> --name <pe-name> \
  --vnet-name <vnet> --subnet <subnet> \
  --private-connection-resource-id <storage-resource-id> \
  --group-id blob --connection-name <connection-name>

# Create private endpoint for ACR
az network private-endpoint create --resource-group <rg> --name <pe-name> \
  --vnet-name <vnet> --subnet <subnet> \
  --private-connection-resource-id <acr-resource-id> \
  --group-id registry --connection-name <connection-name>

# Create private endpoint for SQL
az network private-endpoint create --resource-group <rg> --name <pe-name> \
  --vnet-name <vnet> --subnet <subnet> \
  --private-connection-resource-id <sql-server-resource-id> \
  --group-id sqlServer --connection-name <connection-name>

# Create private DNS zone for the service
az network private-dns zone create --resource-group <rg> \
  --name privatelink.vaultcore.azure.net  # Key Vault
#   --name privatelink.blob.core.windows.net  # Blob
#   --name privatelink.azurecr.io             # ACR
#   --name privatelink.database.windows.net   # SQL

# Link private DNS zone to VNet
az network private-dns link vnet create --resource-group <rg> \
  --zone-name <private-dns-zone> --name <link-name> \
  --virtual-network <vnet> --registration-enabled false

# Create DNS zone group (auto-registers A records)
az network private-endpoint dns-zone-group create --resource-group <rg> \
  --endpoint-name <pe-name> --name default \
  --private-dns-zone <private-dns-zone-resource-id> --zone-name <zone>

# List private endpoints
az network private-endpoint list --resource-group <rg> \
  --query "[].{Name:name,Subnet:subnet.id,Status:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}" -o table

# Show private endpoint connection status
az network private-endpoint show --resource-group <rg> --name <pe-name> \
  --query "privateLinkServiceConnections[0].privateLinkServiceConnectionState"

# Approve pending private endpoint connection (on the resource side)
az network private-endpoint-connection approve --id <pe-connection-id>

# Disable public access on Key Vault (force private-only)
az keyvault update --resource-group <rg> --name <vault> --public-network-access Disabled

# Disable public access on Storage
az storage account update --resource-group <rg> --name <account> \
  --default-action Deny --public-network-access Disabled

# Disable public access on ACR
az acr update --resource-group <rg> --name <registry> --public-network-enabled false
```

### Bicep & ARM Deployments

```bash
# --- Bicep ---

# Validate Bicep template
az deployment group validate --resource-group <rg> \
  --template-file main.bicep --parameters @params.json

# What-if (preview changes without deploying)
az deployment group what-if --resource-group <rg> \
  --template-file main.bicep --parameters @params.json

# Deploy Bicep
az deployment group create --resource-group <rg> --name <deployment-name> \
  --template-file main.bicep --parameters @params.json

# Deploy with inline parameter overrides
az deployment group create --resource-group <rg> --name <deployment-name> \
  --template-file main.bicep --parameters env=prod sku=Standard_v2

# Subscription-level deployment
az deployment sub create --location <region> --name <deployment-name> \
  --template-file main.bicep --parameters @params.json

# Management group-level deployment
az deployment mg create --management-group-id <mg-id> --location <region> \
  --template-file main.bicep

# --- Deployment Operations ---

# List deployments
az deployment group list --resource-group <rg> \
  --query "[].{Name:name,State:properties.provisioningState,Time:properties.timestamp}" -o table

# Show deployment
az deployment group show --resource-group <rg> --name <deployment-name>

# Show deployment outputs (connection strings, IDs, etc.)
az deployment group show --resource-group <rg> --name <deployment-name> \
  --query properties.outputs

# Show failed operations
az deployment operation group list --resource-group <rg> --name <deployment-name> \
  --query "[?properties.provisioningState=='Failed'].{Resource:properties.targetResource.resourceName,Error:properties.statusMessage.error.message}" -o table

# Export existing resource group as ARM/Bicep (reverse-engineer)
az group export --resource-group <rg> --include-parameter-default-value

# Delete deployment history (keeps resources, clears history)
az deployment group delete --resource-group <rg> --name <deployment-name>

# --- Template Specs (shareable templates) ---

# Create template spec
az ts create --resource-group <rg> --name <spec-name> --version 1.0 \
  --template-file main.bicep

# Deploy from template spec
az deployment group create --resource-group <rg> \
  --template-spec <template-spec-resource-id>/versions/1.0
```

### Policy & Governance

```bash
# List policy assignments at resource group scope
az policy assignment list --resource-group <rg> -o table

# List at subscription scope
az policy assignment list --query "[].{Name:displayName,Enforcement:enforcementMode,Scope:scope}" -o table

# Show compliance state summary
az policy state summarize --resource-group <rg> \
  --query "{NonCompliant:results.nonCompliantResources,NonCompliantPolicies:results.nonCompliantPolicies}"

# Detailed non-compliant resources
az policy state list --resource-group <rg> \
  --filter "complianceState eq 'NonCompliant'" \
  --query "[].{Resource:resourceId,Policy:policyDefinitionName,State:complianceState}" -o table

# Trigger policy evaluation (doesn't wait)
az policy state trigger-scan --resource-group <rg> --no-wait

# Create policy assignment
az policy assignment create --name <assignment-name> --display-name <display> \
  --policy <policy-definition-id> --scope <scope> \
  --params '{"effect":{"value":"Deny"}}'

# Create policy assignment with managed identity (for remediation)
az policy assignment create --name <assignment-name> \
  --policy <policy-definition-id> --scope <scope> \
  --mi-system-assigned --location <region> \
  --identity-scope <scope> --role Contributor

# --- Policy Remediation ---

# Create remediation task
az policy remediation create --name <remediation-name> \
  --resource-group <rg> --policy-assignment <assignment-name>

# Check remediation status
az policy remediation show --name <remediation-name> --resource-group <rg> \
  --query "{Status:provisioningState,Succeeded:deploymentStatus.totalDeployments,Failed:deploymentStatus.failedDeployments}"

# List remediations
az policy remediation list --resource-group <rg> -o table

# Delete remediation
az policy remediation delete --name <remediation-name> --resource-group <rg>

# --- Resource Locks ---

# List locks
az lock list --resource-group <rg> -o table

# Create CanNotDelete lock
az lock create --name <lock> --resource-group <rg> --lock-type CanNotDelete \
  --notes "Prevent accidental deletion"

# Create ReadOnly lock (blocks all writes)
az lock create --name <lock> --resource-group <rg> --lock-type ReadOnly

# Delete lock (destructive — confirm with user)
az lock delete --name <lock> --resource-group <rg>

# Lock at resource level
az lock create --name <lock> --resource-group <rg> \
  --resource-name <resource> --resource-type <type> --lock-type CanNotDelete
```

### Cost Management

```bash
# Current month spend by resource group
az consumption usage list --start-date $(date -u +%Y-%m-01) --end-date $(date -u +%Y-%m-%d) \
  --query "[].{RG:instanceName,Cost:pretaxCost,Currency:currency}" -o table

# Budget operations
az consumption budget list -o table
az consumption budget create --budget-name <budget> --amount <n> \
  --category Cost --time-grain Monthly --start-date $(date -u +%Y-%m-01) \
  --end-date $(date -u -d "+1 year" +%Y-%m-01)

# Cost analysis via REST (more powerful)
az rest --method post \
  --url "https://management.azure.com/subscriptions/<sub-id>/providers/Microsoft.CostManagement/query?api-version=2023-11-01" \
  --body '{
    "type": "ActualCost",
    "timeframe": "MonthToDate",
    "dataset": {
      "granularity": "None",
      "aggregation": {"totalCost": {"name": "Cost", "function": "Sum"}},
      "grouping": [{"type": "Dimension", "name": "ResourceGroup"}]
    }
  }'
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

### AKS Cluster Issues
```bash
# Check cluster provisioning state
az aks show -g <rg> -n <cluster> --query "{State:provisioningState,Power:powerState.code,FQDN:fqdn}" -o table

# Check node pool health
az aks nodepool list -g <rg> --cluster-name <cluster> \
  --query "[].{Name:name,State:provisioningState,Count:count,VMSize:vmSize,Mode:mode}" -o table

# AKS diagnose (built-in diagnostics)
az aks kollect --resource-group <rg> --name <cluster> \
  --storage-account <storage> --sas-token <sas>

# Check AKS managed identity permissions
KUBELET_ID=$(az aks show -g <rg> -n <cluster> --query identityProfile.kubeletidentity.clientId -o tsv)
az role assignment list --assignee $KUBELET_ID -o table

# AKS API server connectivity (private clusters)
az aks show -g <rg> -n <cluster> --query "{Private:apiServerAccessProfile.enablePrivateCluster,FQDN:privateFqdn}"
```

### Monitoring & Observability Issues
```bash
# Verify diagnostic settings are enabled on a resource
az monitor diagnostic-settings list --resource <resource-id> -o table

# Check if Container Insights is enabled on AKS
az aks show -g <rg> -n <cluster> \
  --query addonProfiles.omsagent.enabled

# Check Log Analytics agent heartbeat (are logs flowing?)
az monitor log-analytics query --workspace <workspace-id> --analytics-query "
Heartbeat
| where TimeGenerated > ago(30m)
| summarize LastHeartbeat = max(TimeGenerated) by Computer
| where LastHeartbeat < ago(10m)
" -o table

# Check ingestion delays
az monitor log-analytics query --workspace <workspace-id> --analytics-query "
union withsource=TableName *
| where TimeGenerated > ago(1h)
| summarize IngestionDelay = avg(ingestion_time() - TimeGenerated) by TableName
| where IngestionDelay > 5m
| order by IngestionDelay desc
" -o table

# Verify Application Insights is receiving data
az monitor app-insights query --app <app-insights> -g <rg> --analytics-query "
requests
| where timestamp > ago(30m)
| summarize Count = count(), AvgDuration = avg(duration) by bin(timestamp, 5m)
| order by timestamp desc
"
```

### Network Connectivity Issues
```bash
# Test connectivity between resources
az network watcher test-connectivity -g <rg> \
  --source-resource <vm-id> --dest-address <target-ip> --dest-port 443

# Check NSG blocking traffic
az network nic list-effective-nsg -g <rg> -n <nic-name> \
  --query "value[].effectiveSecurityRules[?access=='Deny']"

# Verify private endpoint DNS resolution
az network private-endpoint dns-zone-group list \
  --resource-group <rg> --endpoint-name <pe-name> -o table

# Check AppGW backend health
az network application-gateway show-backend-health -g <rg> -n <agw> \
  --query "backendAddressPools[].backendHttpSettingsCollection[].servers[?health!='Healthy']"
```

## Quick Start Checklist

- [ ] Verify login: `az account show`
- [ ] Confirm correct subscription: `az account list -o table`
- [ ] Set subscription if needed: `az account set -s <name>`
- [ ] Check CLI version: `az version`
- [ ] Update if needed: `az upgrade`
- [ ] Set defaults to reduce repetition: `az configure --defaults group=<rg> location=<region>`
