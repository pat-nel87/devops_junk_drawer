# GitHub Copilot CLI Agent Instructions: Istio Service Mesh + GitOps on AKS

## Project Context
Building an Istio service mesh on Azure Kubernetes Service (AKS) using the cluster extension approach, with all configuration managed via Flux GitOps. The cluster already has:
- AGIC (Application Gateway Ingress Controller) for public HTTPS traffic
- Private nginx ingress for internal traffic
- microservices with external dependencies
- Flux GitOps already configured

## Architecture Goals
1. Use AKS Istio cluster extension (Microsoft-managed control plane)
2. Manage all Istio configuration declaratively via GitOps
3. API Gateway service acts as frontend (behind AGIC) and talks to meshed backend services
4. Start with API Gateway outside the mesh, backend services inside mesh
5. Gradually adopt Istio features without breaking existing functionality

## Repository Structure
**IMPORTANT**: Respect the existing GitOps repository structure. Do not prescribe or suggest structural changes unless explicitly asked. When generating manifests:
- Ask where files should be placed if location is unclear
- Follow existing patterns for namespace organization
- Match existing naming conventions for directories and files
- Use the same kustomization patterns already in use
- Integrate with existing Flux configuration structure

## Coding Guidelines

### 1. Namespace Configuration
- Create namespace manifests with Istio injection labels
- Backend namespaces: `istio-injection: enabled`
- API Gateway namespace: `istio-injection: disabled` (initially)
- Auth/Login services: `istio-injection: disabled` (to avoid OAuth/session issues)

### 2. Deployment Annotations
- Explicitly set sidecar injection per deployment:
  - Backend services: `sidecar.istio.io/inject: "true"`
  - API Gateway (phase 1): `sidecar.istio.io/inject: "false"`
  - Auth services: `sidecar.istio.io/inject: "false"`
- Always include version labels: `version: v1` (for traffic management)

### 3. ServiceEntry Patterns
- Create separate ServiceEntry files per category:
  - Azure services (Key Vault, Storage, Service Bus, SQL)
  - External APIs (Stripe, Twilio, etc.)
  - Auth providers (Azure AD, Auth0, etc.)
- Use DNS resolution for external services
- Location: MESH_EXTERNAL
- Organize by protocol (HTTPS/443, TCP/custom ports)

Example template:
```yaml
apiVersion: networking.istio.io/v1beta1
kind: ServiceEntry
metadata:
  name: <category>-services
  namespace: istio-system
spec:
  hosts:
  - "*.example.com"
  location: MESH_EXTERNAL
  ports:
  - number: 443
    name: https
    protocol: TLS
  resolution: DNS
```

### 4. PeerAuthentication Strategy
- Start with PERMISSIVE mode globally (allows both mTLS and plaintext)
- Namespace-specific overrides for auth services (DISABLE)
- Port-level mTLS configuration when needed
- Don't enable STRICT mode until Phase 4

### 5. Gateway and VirtualService (Phase 3+)
- Create Istio Gateway resource in istio-system namespace
- Use `istio: ingressgateway` selector (cluster extension's gateway)
- VirtualService in the app namespace
- Route AGIC traffic to Istio Gateway, then to services

### 6. Kustomization Files
- Follow existing kustomization.yaml patterns in the repository
- Match the interval settings used elsewhere in the repo
- Use the same Flux sourceRef patterns
- Include health checks for critical Istio resources where appropriate
- Follow existing pruning strategy (observe if other kustomizations use `prune: true` or not)

### 7. Resource Naming Conventions
- Follow existing naming conventions in the repository
- Maintain consistency with current resource naming patterns
- If unclear, use kebab-case as a fallback
- Include namespace in cross-namespace references (FQDN format)
- Suggested patterns for Istio resources (adapt to existing conventions):
  - ServiceEntries: `<category>-<type>` or follow existing external resource naming
  - Gateways: `<app>-gateway` or match existing gateway patterns
  - VirtualServices: `<app>-routes` or match existing routing resource names

### 8. Labels and Selectors
- Always include: `app`, `version`, `component`
- Backend services need consistent labels for Istio observability
- Use `app.kubernetes.io/*` labels where appropriate

### 9. Security Practices
- Never commit sensitive data (use sealed secrets or external secrets)
- AuthorizationPolicies should be explicit (deny by default in production)
- Start with ALLOW-all policies, tighten gradually
- Document why each ServiceEntry is needed

### 10. Comments and Documentation
- Each ServiceEntry should have a comment explaining which services need it
- Document phase rollout plans in comments
- Include troubleshooting notes for common issues (login problems, external connectivity)

## Azure CLI Commands (Don't include in manifests, for reference)
```bash
# Enable Istio cluster extension
az aks mesh enable --resource-group <rg> --name <cluster> --revision asm-1-23

# Check status
az aks show --resource-group <rg> --name <cluster> --query 'serviceMeshProfile'

# Enable Istio addons (optional, for observability)
az aks mesh enable-ingress-gateway --resource-group <rg> --name <cluster> --ingress-gateway-type external
az aks mesh enable-egress-gateway --resource-group <rg> --name <cluster>
```

## Testing Commands
```bash
# Verify Istio control plane
kubectl get pods -n aks-istio-system

# Check sidecar injection
kubectl get pods -n <namespace> -o jsonpath='{.items[*].spec.containers[*].name}'

# Test service connectivity from meshed pod
kubectl exec -it <pod> -c <container> -n <namespace> -- curl http://service.namespace.svc.cluster.local

# Verify ServiceEntries
kubectl get serviceentry -A

# Check mTLS status
istioctl x describe pod <pod> -n <namespace>
```

## Common Patterns to Generate

### Pattern 1: Backend Service with Sidecar
Generate deployments with:
- Sidecar injection enabled
- Proper labels (app, version, component)
- Resource requests/limits
- Liveness/readiness probes
- Service pointing to deployment

### Pattern 2: ServiceEntry for External API
Generate for common services:
- Azure: Key Vault, Storage, SQL, Service Bus, Container Registry
- External: Stripe, Twilio, SendGrid, Auth0, Okta
- Include both HTTPS (443) and service-specific ports

### Pattern 3: Kustomization with Health Checks
Include health checks for:
- Gateway resources
- VirtualService resources
- PeerAuthentication policies

### Pattern 4: AuthorizationPolicy
Start permissive, generate policies for:
- Allow all within namespace
- Allow specific service-to-service communication
- Deny external access except through gateways

## Phase-Specific Instructions

### Phase 1: Foundation Setup
Focus on:
- Namespace creation with injection labels
- ServiceEntry resources for all external dependencies
- Global PERMISSIVE PeerAuthentication
- Kustomization structure

### Phase 2: Backend Service Mesh
Focus on:
- Enable injection on backend namespaces
- Update deployment annotations
- Verify service-to-service communication
- Don't change API Gateway yet

### Phase 3: API Gateway Integration
Focus on:
- Istio Gateway resource
- VirtualService routing
- Update AGIC ingress to point to Istio Gateway
- Enable sidecar on API Gateway deployment

### Phase 4: Hardening
Focus on:
- Switch to STRICT mTLS
- Implement AuthorizationPolicies
- Add DestinationRules (circuit breakers, retries, timeouts)
- Enable request authentication

## Error Prevention

### Avoid These Common Mistakes:
1. Don't use nginx Ingress annotations on Istio Gateway resources
2. Don't enable strict mTLS before all services are meshed
3. Don't mesh auth services without proper ServiceEntry for OAuth providers
4. Don't forget to update AGIC ingress when adding Istio Gateway
5. Don't use cross-namespace service references without FQDN
6. Don't create VirtualServices without corresponding Gateway
7. Don't forget `istio-injection` label on namespaces
8. Don't use HTTP for external HTTPS services in ServiceEntry

### Auth/Login Specific:
- Always create ServiceEntry for OAuth provider domains
- Disable mTLS on auth callback endpoints
- Keep session/cookie services outside mesh initially
- Test OAuth flow after any auth service changes

### External Service Connectivity:
- Default outbound traffic policy should be ALLOW_ANY (permissive)
- Create ServiceEntry BEFORE meshing services that call external APIs
- Use wildcards carefully (*.azure.com vs specific subdomains)
- Test external connectivity after enabling sidecar injection

## Validation Checklist

Before committing, verify:
- [ ] All namespaces have explicit injection labels
- [ ] ServiceEntries cover all external dependencies
- [ ] Kustomization files reference all resources
- [ ] No hardcoded secrets in manifests
- [ ] Labels consistent across related resources
- [ ] Health checks defined for critical resources
- [ ] Comments explain non-obvious configurations
- [ ] YAML is valid (yamllint or kubectl --dry-run)

## Copilot-Specific Hints

When I ask you to:
- "Create a backend service" → Include sidecar injection, proper labels, and service
- "Add external dependency" → Create appropriate ServiceEntry with comments
- "Setup auth" → Create namespace without injection + ServiceEntry for OAuth
- "Create gateway" → Include both Gateway and VirtualService resources
- "Harden security" → Generate AuthorizationPolicy with explicit rules
- "Add observability" → Include Istio telemetry annotations and labels

## Style Preferences
- Follow existing YAML formatting in the repository (indentation, quotes, etc.)
- Match current comment style and verbosity
- Respect existing file organization patterns (single vs multi-resource files)
- Use the same resource grouping strategy already in place
- Default fallbacks if patterns are unclear:
  - Use YAML (not JSON)
  - 2-space indentation
  - Comments above resources explaining purpose
  - Include examples in comments for complex configurations

## When in Doubt
- **First, observe existing patterns in the repository before generating new manifests**
- Ask for clarification on file placement if the existing structure is unclear
- Prefer PERMISSIVE over STRICT for Istio policies
- Prefer explicit over implicit configurations
- Prefer namespace-scoped over cluster-scoped resources (when possible)
- Ask for clarification rather than making assumptions about external dependencies
- When generating similar resources to existing ones, match the existing style exactly

## Success Criteria
The GitOps repo should enable:
1. Zero-downtime Istio adoption
2. Incremental service mesh rollout
3. Rollback capability via Git history
4. Clear audit trail of all changes
5. No disruption to existing AGIC/nginx ingress
6. Preserved functionality of auth/login flows
7. Continued external service connectivity
