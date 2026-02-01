# MCP Sidecar Architecture with Gateway Discovery

## Overview

This document describes an architectural pattern for integrating Model Context Protocol (MCP) servers into a Kubernetes microservices environment using a sidecar pattern with centralized gateway discovery.

## Architecture Summary

- **Per-Service MCP Sidecars**: Each microservice gets a lightweight MCP server as a sidecar container
- **Central MCP Gateway**: A discovery and routing layer that aggregates all MCP sidecars
- **Local Diagnostics**: Sidecars access their service via localhost for zero-latency diagnostics
- **GitOps Integration**: Fully compatible with Flux-based deployment workflows

---

## High-Level Architecture

### Component Overview

```
Developer Machine
├── Claude Desktop (MCP Client)
└── kubectl port-forward → MCP Gateway

Azure Kubernetes Service
├── platform-tools namespace
│   ├── MCP Gateway (Discovery & Routing)
│   └── Service Discovery (K8s API + Istio)
│
└── production namespace
    ├── Payment Service Pod
    │   ├── payment-service container (:8080)
    │   └── MCP sidecar container (:3000)
    │
    ├── User Service Pod
    │   ├── user-service container (:8080)
    │   └── MCP sidecar container (:3000)
    │
    ├── MQTT Publisher Pod
    │   ├── mqtt-publisher container (:8080)
    │   └── MCP sidecar container (:3000)
    │
    └── ... (33 more services)
```

### Network Flow

```
Claude Desktop (laptop)
    ↓ [MCP Protocol over port-forward]
MCP Gateway (AKS)
    ↓ [Service Discovery via K8s API]
    ↓ [Route to specific sidecar]
MCP Sidecar (in target pod)
    ↓ [localhost access]
Application Container
    ↓ [optional: query external services]
Prometheus / Istio / Databases
```

---

## Component Details

### 1. MCP Gateway

**Purpose**: Centralized discovery and request routing

**Responsibilities**:
- Discovers all MCP-enabled services via Kubernetes API
- Maintains registry of available MCP sidecars
- Routes tool calls to appropriate sidecars
- Provides unified interface to MCP clients
- Enforces authentication and RBAC
- Implements audit logging

**Key Features**:
- **Service Discovery**: Watches K8s API for services with `mcp-enabled=true` label
- **Tool Caching**: Maintains cached registry of available tools (refresh every 5 min)
- **Connection Pooling**: Reuses connections to sidecars for efficiency
- **Health Checking**: Monitors sidecar availability
- **Request Routing**: Parses tool names like `payment-service.get_health` and routes accordingly

**Implementation Details**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mcp-gateway
  namespace: platform-tools
spec:
  replicas: 2
  template:
    spec:
      serviceAccountName: mcp-gateway
      containers:
      - name: gateway
        image: your-registry/mcp-gateway:latest
        ports:
        - containerPort: 3000
          name: http
        env:
        - name: DISCOVERY_INTERVAL
          value: "300s"
        - name: CACHE_TTL
          value: "300s"
        - name: ALLOWED_NAMESPACES
          value: "production,staging"
```

**RBAC Requirements**:
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: mcp-gateway
rules:
- apiGroups: [""]
  resources: ["services", "endpoints"]
  verbs: ["list", "watch", "get"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["list", "get"]
```

### 2. MCP Sidecar

**Purpose**: Lightweight MCP server exposing service-specific diagnostic tools

**Responsibilities**:
- Expose generic diagnostic tools (health, metrics, logs)
- Load service-specific tools from ConfigMaps
- Access main container via localhost
- Query Istio Envoy sidecar for mesh metrics
- Scrape Prometheus metrics
- Execute diagnostic commands

**Generic Tools** (available in every sidecar):
- `get_health` - Query health endpoint on localhost
- `get_metrics` - Scrape Prometheus metrics endpoint
- `get_logs` - Tail application logs via shared volume
- `query_envoy` - Get Istio sidecar statistics
- `check_endpoints` - Validate service endpoints
- `get_env_vars` - List container environment variables

**Service-Specific Tools** (loaded from ConfigMap):
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: payment-service-mcp-tools
  namespace: production
data:
  tools.yaml: |
    - name: check_transaction_status
      description: Query status of a payment transaction
      endpoint: /admin/transaction/{id}
      method: GET
      
    - name: retry_failed_payment
      description: Retry a failed payment transaction
      endpoint: /admin/retry/{id}
      method: POST
      
    - name: check_stripe_connection
      description: Verify Stripe API connectivity
      command: curl -f https://api.stripe.com/v1/health
      
    - name: get_payment_queue_depth
      description: Check payment processing queue depth
      prometheus_query: payment_queue_depth
```

**Container Specification**:
```yaml
- name: mcp-sidecar
  image: your-registry/mcp-sidecar:latest
  ports:
  - containerPort: 3000
    name: mcp
  env:
  - name: SERVICE_NAME
    value: "payment-service"
  - name: SERVICE_PORT
    value: "8080"
  - name: PROMETHEUS_URL
    value: "http://prometheus.monitoring.svc:9090"
  - name: TOOLS_CONFIG
    value: "/etc/mcp/tools.yaml"
  volumeMounts:
  - name: logs
    mountPath: /var/log/app
    readOnly: true
  - name: mcp-tools
    mountPath: /etc/mcp
  resources:
    requests:
      cpu: 10m
      memory: 32Mi
    limits:
      cpu: 50m
      memory: 64Mi
```

### 3. Service Discovery

**Mechanism**: Label-based discovery via Kubernetes API

**Discovery Query**:
```bash
kubectl get services -l mcp-enabled=true -o json
```

**Service Label**:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: payment-service-mcp
  labels:
    app: payment-service
    mcp-enabled: "true"
    mcp-version: "v1"
spec:
  selector:
    app: payment-service
  ports:
  - name: mcp
    port: 3000
    targetPort: mcp
```

**Istio Integration**:
The gateway can also query Istio for service mesh topology:
```bash
kubectl get virtualservices,destinationrules -o json
```

---

## Request Flow Examples

### Example 1: Check Payment Service Health

```
1. Developer asks Claude: "Check payment service health"

2. Claude Desktop → MCP Gateway
   Request: list_tools()

3. Gateway → Service Discovery
   Query: kubectl get svc -l mcp-enabled=true
   Response: [payment-service, user-service, mqtt-publisher, ...]

4. Gateway → payment-service-mcp sidecar
   Request: What tools do you have?

5. payment-service-mcp → Gateway
   Response: [get_health, get_metrics, check_transaction_status, ...]

6. Gateway → Claude Desktop
   Response: Available tools with full list

7. Claude decides to call: payment-service.get_health

8. Claude Desktop → Gateway
   Request: call_tool("payment-service.get_health")

9. Gateway → payment-service-mcp
   Route: Execute get_health

10. payment-service-mcp → payment-service container
    HTTP GET http://localhost:8080/health

11. payment-service container → payment-service-mcp
    Response: {"status": "healthy", "database": "connected"}

12. payment-service-mcp → Prometheus
    Query: rate(payment_service_errors_total[5m])

13. Prometheus → payment-service-mcp
    Response: error_rate: 0.02

14. payment-service-mcp → Gateway
    Response: {
      "health": "healthy",
      "database": "connected",
      "error_rate": 0.02,
      "latency_p99": 145
    }

15. Gateway → Claude Desktop
    Response: Formatted diagnostic data

16. Claude → Developer
    "Payment service is healthy. Database connected, 
     error rate 2%, p99 latency 145ms"
```

### Example 2: Investigate MQTT Publisher Issues

```
1. Developer: "Why is mqtt-publisher failing to connect to HiveMQ?"

2. Claude calls: mqtt-publisher.check_hivemq_connection

3. MCP Gateway routes to: mqtt-publisher-mcp sidecar

4. Sidecar executes custom tool:
   - Checks local MQTT client status
   - Queries HiveMQ broker health endpoint
   - Inspects topic subscriptions
   - Verifies TLS certificates

5. Sidecar returns comprehensive diagnostic:
   {
     "broker_reachable": false,
     "last_error": "connection timeout",
     "certificate_valid": true,
     "topic_subscriptions": ["sensor/+/data"]
   }

6. Claude analyzes and responds:
   "The HiveMQ broker is unreachable with connection timeout.
    The TLS certificate is valid. This suggests a network issue.
    Let me check the firewall rules..."
```

---

## Data Access Patterns

### Localhost Access (Primary Pattern)

```
MCP Sidecar ─────localhost:8080────→ Application Container
            ←────health/metrics─────
```

**Benefits**:
- Zero network hops
- No network policy configuration needed
- Lowest possible latency
- No authentication required (same pod)

### Shared Volume Access

```
Application Container → writes logs → Shared emptyDir volume
                                            ↓
MCP Sidecar ← reads logs ← Shared emptyDir volume
```

**Use Cases**:
- Log file access
- Temporary diagnostic dumps
- Configuration file inspection

### External Service Access

```
MCP Sidecar → Prometheus (metrics queries)
            → Istio Control Plane (mesh topology)
            → PostgreSQL (query stats)
            → External APIs (health checks)
```

**Requires**:
- Network policies allowing sidecar egress
- Service account permissions
- Credentials management via Secrets

### Istio Envoy Access

```
MCP Sidecar ─────localhost:15000────→ Envoy Sidecar
            ←────stats/config_dump───
```

**Capabilities**:
- Query circuit breaker status
- Get upstream connection stats
- Inspect route configuration
- Retrieve trace spans
- Check retry/timeout settings

---

## Security Model

### Trust Boundaries

```
┌─────────────────────────────────────────────┐
│ Developer Machine (Untrusted)               │
│   - Claude Desktop (MCP Client)             │
│   - kubectl port-forward                    │
└──────────────────┬──────────────────────────┘
                   │ Authentication required
                   │ (Token/mTLS)
                   ▼
┌─────────────────────────────────────────────┐
│ MCP Gateway (Trust Boundary)                │
│   - Authenticates clients                   │
│   - Enforces RBAC                           │
│   - Audit logging                           │
│   - Rate limiting                           │
└──────────────────┬──────────────────────────┘
                   │ Authenticated internal traffic
                   │ (Service account tokens)
                   ▼
┌─────────────────────────────────────────────┐
│ MCP Sidecars (Service Level)                │
│   - Per-service isolation                   │
│   - Limited scope                           │
│   - No cross-service access                 │
└─────────────────────────────────────────────┘
```

### RBAC Implementation

**Gateway Service Account**:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: mcp-gateway
  namespace: platform-tools
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: mcp-gateway
rules:
- apiGroups: [""]
  resources: ["services", "endpoints", "pods"]
  verbs: ["list", "watch", "get"]
- apiGroups: ["networking.istio.io"]
  resources: ["virtualservices", "destinationrules"]
  verbs: ["list", "get"]
```

**Sidecar Service Accounts** (per service tier):
```yaml
# Critical production services
apiVersion: v1
kind: ServiceAccount
metadata:
  name: mcp-production-critical
  namespace: production
---
# Standard production services
apiVersion: v1
kind: ServiceAccount
metadata:
  name: mcp-production-standard
  namespace: production
---
# Development services
apiVersion: v1
kind: ServiceAccount
metadata:
  name: mcp-development
  namespace: development
```

### Network Policies

**Restrict MCP Gateway Access**:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: mcp-gateway-ingress
  namespace: platform-tools
spec:
  podSelector:
    matchLabels:
      app: mcp-gateway
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: istio-system
    ports:
    - protocol: TCP
      port: 3000
```

**Restrict Sidecar Access**:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: mcp-sidecar-access
  namespace: production
spec:
  podSelector:
    matchLabels:
      mcp-enabled: "true"
  policyTypes:
  - Ingress
  ingress:
  # Only allow MCP gateway to connect to sidecars
  - from:
    - namespaceSelector:
        matchLabels:
          name: platform-tools
      podSelector:
        matchLabels:
          app: mcp-gateway
    ports:
    - protocol: TCP
      port: 3000
```

### Authentication Options

**Option 1: Token-based Authentication**
```yaml
# Gateway validates bearer tokens
Authorization: Bearer <jwt-token>
```

**Option 2: Mutual TLS**
```yaml
# Certificate-based authentication between client and gateway
# Gateway presents cert to sidecars
```

**Option 3: Service Mesh mTLS**
```yaml
# Leverage Istio's automatic mTLS
# All pod-to-pod traffic encrypted and authenticated
```

### Audit Logging

Every request logged with:
- Timestamp
- Client identity (user/service account)
- Target service and tool
- Request parameters
- Response status
- Execution time

```json
{
  "timestamp": "2026-01-31T10:15:30Z",
  "client": "user@example.com",
  "service": "payment-service",
  "tool": "check_transaction_status",
  "params": {"transaction_id": "tx_12345"},
  "status": "success",
  "duration_ms": 45
}
```

---

## Resource Considerations

### Per-Service Overhead

**MCP Sidecar Container**:
- CPU Request: 10m
- CPU Limit: 50m
- Memory Request: 32Mi
- Memory Limit: 64Mi
- Container Image Size: ~10-15MB (distroless)

### Total Cluster Overhead (36 services)

- **CPU**: 36 × 10m = 360m (0.36 cores)
- **Memory**: 36 × 32Mi = 1,152Mi (~1.1 GB)
- **Storage**: 36 × 15MB = 540MB (images)

**MCP Gateway**:
- CPU Request: 100m
- CPU Limit: 500m
- Memory Request: 128Mi
- Memory Limit: 256Mi
- Replicas: 2 (for HA)

### Network Overhead

- Gateway ↔ Sidecar: ~1KB per tool call
- Sidecar ↔ App Container: negligible (localhost)
- Estimated total: <100KB/s for moderate usage

### Optimization Strategies

1. **Image Optimization**: Use distroless or scratch-based images
2. **Lazy Loading**: Only load service-specific tools when first accessed
3. **Tool Caching**: Cache tool definitions at gateway level
4. **Connection Pooling**: Reuse HTTP connections to sidecars
5. **Horizontal Scaling**: Scale gateway independently of services

---

## GitOps Integration (Flux)

### Repository Structure

```
flux-config/
├── infrastructure/
│   ├── mcp-gateway/
│   │   ├── namespace.yaml
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── serviceaccount.yaml
│   │   ├── rbac.yaml
│   │   └── kustomization.yaml
│   │
│   └── monitoring/
│       └── prometheus/
│           └── mcp-servicemonitor.yaml
│
├── bases/
│   └── mcp-sidecar/
│       ├── sidecar-patch.yaml           # Common sidecar config
│       ├── common-tools-config.yaml     # Generic tools
│       ├── serviceaccount.yaml          # Sidecar SA template
│       └── kustomization.yaml
│
└── services/
    ├── payment-service/
    │   ├── deployment.yaml              # Includes sidecar via patch
    │   ├── mcp-service.yaml             # ClusterIP for MCP port
    │   ├── mcp-tools-config.yaml        # Service-specific tools
    │   └── kustomization.yaml
    │
    ├── user-service/
    │   ├── deployment.yaml
    │   ├── mcp-service.yaml
    │   ├── mcp-tools-config.yaml
    │   └── kustomization.yaml
    │
    └── mqtt-publisher/
        ├── deployment.yaml
        ├── mcp-service.yaml
        ├── mcp-tools-config.yaml
        └── kustomization.yaml
```

### Kustomize Patch for Sidecar

**bases/mcp-sidecar/sidecar-patch.yaml**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: not-important
spec:
  template:
    metadata:
      labels:
        mcp-enabled: "true"
    spec:
      containers:
      - name: mcp-sidecar
        image: your-registry/mcp-sidecar:v1.0.0
        ports:
        - containerPort: 3000
          name: mcp
        env:
        - name: SERVICE_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.labels['app']
        - name: SERVICE_PORT
          value: "8080"
        - name: PROMETHEUS_URL
          value: "http://prometheus.monitoring.svc:9090"
        - name: TOOLS_CONFIG
          value: "/etc/mcp/tools.yaml"
        volumeMounts:
        - name: mcp-tools
          mountPath: /etc/mcp
        - name: logs
          mountPath: /var/log/app
          readOnly: true
        resources:
          requests:
            cpu: 10m
            memory: 32Mi
          limits:
            cpu: 50m
            memory: 64Mi
      volumes:
      - name: mcp-tools
        configMap:
          name: mcp-tools
      - name: logs
        emptyDir: {}
```

### Service Kustomization

**services/payment-service/kustomization.yaml**:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: production

resources:
- deployment.yaml
- mcp-service.yaml
- mcp-tools-config.yaml

patches:
- path: ../../bases/mcp-sidecar/sidecar-patch.yaml
  target:
    kind: Deployment
    name: payment-service

configMapGenerator:
- name: mcp-tools
  files:
  - tools.yaml=mcp-tools-config.yaml
```

### Flux HelmRelease for Gateway

**infrastructure/mcp-gateway/helmrelease.yaml**:
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: mcp-gateway
  namespace: platform-tools
spec:
  interval: 5m
  chart:
    spec:
      chart: ./charts/mcp-gateway
      sourceRef:
        kind: GitRepository
        name: flux-system
        namespace: flux-system
  values:
    replicas: 2
    image:
      repository: your-registry/mcp-gateway
      tag: v1.0.0
    serviceAccount:
      create: true
      name: mcp-gateway
    rbac:
      create: true
    service:
      type: ClusterIP
      port: 3000
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 256Mi
```

### Stamp Pattern Integration

If using a stamp-based pattern for multiple environments:

```
stamps/
├── production/
│   ├── kustomization.yaml
│   └── services/
│       ├── payment-service/
│       │   └── mcp-tools-config.yaml    # Prod-specific tools
│       └── user-service/
│           └── mcp-tools-config.yaml
│
└── staging/
    ├── kustomization.yaml
    └── services/
        ├── payment-service/
        │   └── mcp-tools-config.yaml    # Staging-specific tools
        └── user-service/
            └── mcp-tools-config.yaml
```

---

## Deployment Strategy

### Phase 1: Gateway Setup (Week 1)

1. Deploy MCP Gateway to `platform-tools` namespace
2. Configure RBAC and service accounts
3. Verify service discovery works
4. Set up monitoring and logging

**Validation**:
```bash
kubectl port-forward -n platform-tools svc/mcp-gateway 3000:3000
curl http://localhost:3000/health
```

### Phase 2: Pilot Services (Week 2)

1. Select 2-3 non-critical services for pilot
2. Add MCP sidecar via Kustomize patch
3. Create service-specific tool ConfigMaps
4. Deploy and test

**Pilot Services Recommendation**:
- One simple service (minimal dependencies)
- One complex service (database, external APIs)
- One batch/async service (queue processing)

### Phase 3: Rollout (Weeks 3-4)

1. Document lessons learned from pilot
2. Refine sidecar configuration
3. Create rollout plan for remaining 33 services
4. Deploy in waves:
   - Week 3: 15 services
   - Week 4: 18 services

### Phase 4: Optimization (Week 5)

1. Analyze resource usage patterns
2. Tune CPU/memory limits
3. Implement caching strategies
4. Add custom tools based on feedback

---

## Monitoring and Observability

### Prometheus Metrics

**Gateway Metrics**:
```
mcp_gateway_requests_total{service, tool, status}
mcp_gateway_request_duration_seconds{service, tool}
mcp_gateway_discovery_services_total
mcp_gateway_sidecar_health{service}
```

**Sidecar Metrics**:
```
mcp_sidecar_tool_executions_total{tool, status}
mcp_sidecar_tool_duration_seconds{tool}
mcp_sidecar_localhost_requests_total{endpoint}
```

### ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: mcp-gateway
  namespace: platform-tools
spec:
  selector:
    matchLabels:
      app: mcp-gateway
  endpoints:
  - port: metrics
    interval: 30s
```

### Grafana Dashboard

Key panels:
- Request rate per service
- P50/P95/P99 latency
- Error rate by tool
- Service discovery lag
- Sidecar health status
- Resource usage trends

### Logging

**Structured Logging Format**:
```json
{
  "timestamp": "2026-01-31T10:15:30Z",
  "level": "info",
  "component": "gateway",
  "message": "Tool executed successfully",
  "service": "payment-service",
  "tool": "get_health",
  "duration_ms": 42,
  "client_id": "claude-desktop-user123"
}
```

**Log Aggregation**:
- Send to Azure Log Analytics or ELK stack
- Retain for compliance (90 days recommended)
- Alert on error rate spikes

---

## Troubleshooting Guide

### Gateway Cannot Discover Services

**Symptoms**:
- `mcp_gateway_discovery_services_total` metric is 0
- Gateway logs show "no services found"

**Diagnosis**:
```bash
# Check RBAC permissions
kubectl auth can-i list services --as=system:serviceaccount:platform-tools:mcp-gateway

# Verify service labels
kubectl get svc -l mcp-enabled=true --all-namespaces

# Check gateway logs
kubectl logs -n platform-tools deploy/mcp-gateway
```

**Common Fixes**:
- Ensure services have `mcp-enabled=true` label
- Verify ClusterRole bindings are correct
- Check namespace selectors in RBAC

### Sidecar Cannot Access Main Container

**Symptoms**:
- Health checks failing
- "Connection refused" errors in sidecar logs

**Diagnosis**:
```bash
# Exec into sidecar
kubectl exec -it <pod> -c mcp-sidecar -- sh

# Test localhost connectivity
curl http://localhost:8080/health

# Check if main container is listening
netstat -tlnp
```

**Common Fixes**:
- Verify main container binds to 0.0.0.0, not 127.0.0.1
- Check firewall rules within pod
- Ensure health endpoint path is correct

### High Latency from Gateway to Sidecar

**Symptoms**:
- `mcp_gateway_request_duration_seconds` > 1s
- Claude responses are slow

**Diagnosis**:
```bash
# Check network policies
kubectl get networkpolicies -n production

# Test direct connectivity
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- \
  curl http://payment-service-mcp.production.svc:3000/health

# Check Istio routing
istioctl proxy-config routes deploy/mcp-gateway -n platform-tools
```

**Common Fixes**:
- Review network policies blocking traffic
- Check Istio VirtualService configurations
- Verify DNS resolution is fast
- Consider increasing gateway connection pool size

### Tool Execution Failures

**Symptoms**:
- Specific tools return errors
- Works manually but fails via MCP

**Diagnosis**:
```bash
# Check sidecar logs
kubectl logs <pod> -c mcp-sidecar

# Verify ConfigMap is mounted
kubectl exec <pod> -c mcp-sidecar -- cat /etc/mcp/tools.yaml

# Test tool manually
kubectl exec <pod> -c mcp-sidecar -- <command>
```

**Common Fixes**:
- Validate tool configuration YAML syntax
- Ensure required environment variables are set
- Check file permissions for mounted volumes
- Verify external service connectivity

---

## Client Configuration

### Claude Desktop Setup

**macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`
**Windows**: `%APPDATA%\Claude\claude_desktop_config.json`
**Linux**: `~/.config/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "kubernetes-diagnostics": {
      "url": "http://localhost:3000",
      "transport": "sse",
      "description": "Diagnostics for 36 microservices in AKS"
    }
  }
}
```

### Port-Forward Setup

**Manual Port-Forward**:
```bash
kubectl port-forward -n platform-tools svc/mcp-gateway 3000:3000
```

**Automated Port-Forward** (shell script):
```bash
#!/bin/bash
# mcp-connect.sh

NAMESPACE="platform-tools"
SERVICE="mcp-gateway"
LOCAL_PORT=3000

echo "Establishing port-forward to MCP Gateway..."
kubectl port-forward -n $NAMESPACE svc/$SERVICE $LOCAL_PORT:3000 &
PF_PID=$!

echo "Port-forward established (PID: $PF_PID)"
echo "Connect Claude Desktop to http://localhost:$LOCAL_PORT"
echo "Press Ctrl+C to disconnect"

trap "kill $PF_PID" EXIT
wait $PF_PID
```

### VS Code with MCP Extension

If using VS Code with an MCP extension:

```json
// .vscode/settings.json
{
  "mcp.servers": [
    {
      "name": "kubernetes-diagnostics",
      "url": "http://localhost:3000",
      "autoConnect": true
    }
  ]
}
```

---

## Advanced Patterns

### Multi-Cluster Support

For managing multiple AKS clusters:

```
MCP Gateway (Cluster 1)
    ↓
MCP Gateway (Cluster 2) 
    ↓
MCP Gateway (Cluster 3)
    ↓
Claude Desktop
```

Each cluster has its own gateway, and a meta-gateway aggregates them.

### Cross-Namespace Diagnostics

Allow specific services to query other namespaces:

```yaml
# Extended RBAC for user-service MCP sidecar
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: mcp-cross-namespace
  namespace: database
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["list", "get"]
```

### Custom Tool Development

Template for creating custom tools:

```python
# Example: Custom PostgreSQL query tool
class PostgreSQLQueryTool:
    def __init__(self, connection_string):
        self.conn = psycopg2.connect(connection_string)
    
    def execute(self, params):
        query = params.get("query")
        # Validate query is read-only
        if not query.lower().startswith("select"):
            raise ValueError("Only SELECT queries allowed")
        
        cursor = self.conn.cursor()
        cursor.execute(query)
        return cursor.fetchall()
```

### Caching Strategy

Implement response caching in sidecars for frequently accessed data:

```go
type CachedTool struct {
    cache     *cache.Cache
    ttl       time.Duration
    underlying Tool
}

func (t *CachedTool) Execute(params map[string]interface{}) (interface{}, error) {
    cacheKey := generateCacheKey(params)
    
    if cached, found := t.cache.Get(cacheKey); found {
        return cached, nil
    }
    
    result, err := t.underlying.Execute(params)
    if err == nil {
        t.cache.Set(cacheKey, result, t.ttl)
    }
    
    return result, err
}
```

---

## Future Enhancements

### Planned Features

1. **Auto-generated Tools**: Introspect OpenAPI specs to auto-generate MCP tools
2. **Trace Integration**: Link MCP requests to distributed traces
3. **Chaos Engineering**: Tools to inject faults for testing
4. **Cost Analysis**: Tools to query Azure cost data per service
5. **GitOps Validation**: Tools to verify Flux sync status
6. **Canary Analysis**: Tools to compare metrics between deployments

### Scaling Considerations

As the system grows:
- Implement tool pagination for large service counts
- Add gateway sharding by namespace
- Consider event-driven updates instead of polling
- Implement GraphQL layer for complex queries

---

## Security Hardening Checklist

- [ ] Enable mutual TLS between gateway and sidecars
- [ ] Implement API key rotation for client authentication
- [ ] Set up audit log retention and analysis
- [ ] Configure network policies to restrict sidecar egress
- [ ] Enable Pod Security Standards (restricted)
- [ ] Implement rate limiting per client
- [ ] Set up alerts for suspicious access patterns
- [ ] Encrypt sensitive tool configurations in ConfigMaps
- [ ] Regularly scan MCP sidecar images for vulnerabilities
- [ ] Implement least-privilege RBAC for all components

---

## Performance Benchmarks

### Expected Performance (36 services)

| Metric | Target | Measured |
|--------|--------|----------|
| Tool discovery time | < 100ms | TBD |
| Simple tool execution (health check) | < 50ms | TBD |
| Complex tool execution (DB query) | < 200ms | TBD |
| Concurrent requests (gateway) | > 1000/s | TBD |
| Memory per sidecar | < 40Mi | TBD |
| CPU per sidecar | < 15m | TBD |

### Load Testing

```bash
# Use hey or k6 for load testing
hey -n 10000 -c 100 http://localhost:3000/tools/payment-service.get_health
```

---

## Cost Analysis

### Compute Costs (Azure AKS)

Assuming D4s_v3 nodes ($0.192/hour):
- MCP Gateway: ~0.1 cores = $0.019/hour = $14/month
- 36 Sidecars: ~0.36 cores = $0.069/hour = $50/month
- **Total**: ~$64/month additional compute cost

### Storage Costs

- Container images: ~540MB = negligible
- Logs (Azure Monitor): ~$2/GB/month, estimate 10GB = $20/month

### Total Estimated Cost

**~$84/month** for full MCP infrastructure across 36 services

### Cost Optimization

- Use spot instances for non-production environments
- Implement aggressive log retention policies
- Cache tool results to reduce repeated queries
- Right-size gateway replicas based on actual load

---

## Conclusion

This architecture provides:
- **Scalability**: Add new services without modifying the gateway
- **Isolation**: Each service's diagnostics are self-contained
- **GitOps Integration**: Fully compatible with Flux workflows
- **Security**: Multiple layers of authentication and authorization
- **Observability**: Comprehensive metrics and logging
- **Minimal Overhead**: <1 core and <2GB memory for 36 services

The sidecar pattern keeps diagnostic logic close to the data while the gateway provides a unified interface for Claude and other MCP clients.

---

## References

- [Model Context Protocol Specification](https://spec.modelcontextprotocol.io/)
- [Kubernetes Sidecar Pattern](https://kubernetes.io/docs/concepts/workloads/pods/#how-pods-manage-multiple-containers)
- [Istio Service Mesh](https://istio.io/latest/docs/)
- [Flux GitOps](https://fluxcd.io/flux/)
- [Azure Kubernetes Service](https://learn.microsoft.com/en-us/azure/aks/)

---

## Appendix

### Example Tool Definitions

**Generic Health Check Tool**:
```yaml
name: get_health
description: Query service health endpoint
type: http
config:
  method: GET
  url: http://localhost:8080/health
  timeout: 5s
  expected_status: 200
```

**Custom Prometheus Query Tool**:
```yaml
name: get_error_rate
description: Query 5-minute error rate from Prometheus
type: prometheus
config:
  query: rate(http_requests_total{job="$SERVICE_NAME",status=~"5.."}[5m])
  prometheus_url: http://prometheus.monitoring.svc:9090
```

**Database Query Tool**:
```yaml
name: get_connection_pool_stats
description: Query PostgreSQL connection pool statistics
type: database
config:
  connection_string: $DATABASE_URL
  query: SELECT * FROM pg_stat_activity WHERE datname = '$DATABASE_NAME'
  read_only: true
```

### Sample ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: payment-service-mcp-tools
  namespace: production
data:
  tools.yaml: |
    tools:
      - name: check_transaction_status
        description: Query the status of a payment transaction
        type: http
        config:
          method: GET
          url: http://localhost:8080/admin/transaction/{transaction_id}
          auth:
            type: header
            header: X-Admin-Token
            value_from: ADMIN_TOKEN_SECRET
      
      - name: get_payment_metrics
        description: Retrieve payment processing metrics
        type: prometheus
        config:
          queries:
            - name: success_rate
              query: rate(payments_successful_total[5m]) / rate(payments_total[5m])
            - name: avg_amount
              query: avg(payment_amount_usd)
      
      - name: check_stripe_connection
        description: Verify connectivity to Stripe API
        type: command
        config:
          command: curl
          args:
            - -f
            - -m
            - "5"
            - https://api.stripe.com/v1/health
      
      - name: get_queue_depth
        description: Check payment processing queue depth
        type: prometheus
        config:
          query: payment_queue_depth{queue="processing"}
