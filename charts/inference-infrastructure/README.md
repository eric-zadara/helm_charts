# Inference Infrastructure

Umbrella chart that deploys LiteLLM API proxy and an Envoy Gateway for LLM inference traffic.

## What's Included

| Component | Type | Description | Default |
|-----------|------|-------------|---------|
| LiteLLM Proxy | Subchart dependency | Multi-tenant OpenAI-compatible API proxy (bundles its own PostgreSQL via CNPG and Valkey as sub-dependencies) | Enabled |
| Gateway API resources | Direct templates | EnvoyProxy config, GatewayClass, and Gateway for Envoy Gateway | Enabled |

> **Note:** PostgreSQL (CNPG) and Valkey are **not** direct dependencies of this chart. They are bundled inside the `litellm-proxy` subchart and deployed automatically when `litellm-proxy.database.internal.enabled` and `litellm-proxy.cache.internal.enabled` are true (the defaults).

## Architecture

```
                    External Traffic
                          |
                          v
                +-------------------+
                |  Envoy Gateway    |
                |  (GatewayClass +  |
                |   Gateway)        |
                +-------------------+
                          |
                    HTTPRoute(s)
                          |
              +-----------+-----------+
              |                       |
              v                       v
    +-------------------+   +-------------------+
    |  LiteLLM Proxy    |   | Inference Models  |
    |  (API routing)    |   | (via EPP/KServe)  |
    +-------------------+   +-------------------+
          |           |
          v           v
    +-----------+  +----------+
    | PostgreSQL|  |  Valkey  |
    |  (CNPG)   |  | (cache)  |
    +-----------+  +----------+
    [  bundled via litellm-proxy  ]
```

## Prerequisites

This chart requires the following sibling charts to be installed first:

1. **inference-crds** -- Custom Resource Definitions for CNPG, Envoy Gateway, and Gateway API
2. **inference-operators** -- Operators that reconcile those CRDs (CNPG operator, Envoy Gateway controller)

The chart's CI annotation `testing/prerequisites: "inference-crds,inference-operators"` documents this ordering.

## Quick Start

```bash
# 1. Install CRDs
helm install crds ./charts/inference-crds

# 2. Install operators
helm install operators ./charts/inference-operators

# 3. Install infrastructure (LiteLLM + Gateway)
helm install infra ./charts/inference-infrastructure

# 4. Install model serving stack
helm install stack ./charts/inference-stack
```

Verify the deployment:

```bash
# Check all pods are running
kubectl get pods

# Check LiteLLM is connected
kubectl logs -l app.kubernetes.io/name=litellm-proxy | head -20

# Check Gateway is programmed
kubectl get gateway
```

## Service Naming Convention

When using release name `infra`, these services are created:

| Service | Name | Description |
|---------|------|-------------|
| PostgreSQL pooler | `infra-postgresql-pooler-rw` | PgBouncer connection pooler |
| PostgreSQL secret | `infra-postgresql-app` | Database credentials |
| Valkey service | `infra-valkey-primary` | Redis-compatible cache |
| Valkey auth secret | `infra-valkey` | Cache credentials |
| Gateway | `infra-gateway` | Envoy Gateway for external traffic |

LiteLLM is pre-configured to connect to these services automatically.

## Values

### Gateway Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `gateway.enabled` | bool | `true` | Create Gateway API resources (EnvoyProxy, GatewayClass, Gateway) |
| `gateway.className` | string | `"llm-gateway"` | GatewayClass name (referenced by HTTPRoutes across the platform) |
| `gateway.service.type` | string | `"LoadBalancer"` | Envoy proxy Service type (LoadBalancer, ClusterIP, NodePort) |
| `gateway.service.annotations` | object | AWS LBC internet-facing | Annotations for the Envoy proxy Service |
| `gateway.listeners.http.enabled` | bool | `true` | Enable HTTP listener |
| `gateway.listeners.http.port` | int | `80` | HTTP listener port |
| `gateway.listeners.https.enabled` | bool | `false` | Enable HTTPS listener |
| `gateway.listeners.https.port` | int | `443` | HTTPS listener port |
| `gateway.listeners.https.hostname` | string | `""` | Hostname for TLS (e.g. `"llm.example.com"`). Omit for wildcard. |
| `gateway.listeners.https.certificateRef` | string | `"llm-gateway-tls"` | Name of the TLS Secret (auto-created by cert-manager if enabled) |
| `gateway.listeners.https.certManager.enabled` | bool | `true` | Add cert-manager annotation on Gateway for automatic certificate provisioning |
| `gateway.listeners.https.certManager.clusterIssuer` | string | `"letsencrypt-prod"` | ClusterIssuer name (must exist in cluster) |

### LiteLLM Proxy

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `litellm-proxy.enabled` | bool | `true` | Deploy LiteLLM proxy |
| `litellm-proxy.database.internal.enabled` | bool | `true` | Deploy bundled PostgreSQL (CNPG) |
| `litellm-proxy.cache.internal.enabled` | bool | `true` | Deploy bundled Valkey cache |
| `litellm-proxy.httpRoute.enabled` | bool | `true` | Create HTTPRoute to wire LiteLLM to the Gateway |
| `litellm-proxy.httpRoute.gateway.name` | string | `""` | Gateway name for HTTPRoute (defaults to release-name gateway) |
| `litellm-proxy.httpRoute.gateway.namespace` | string | `""` | Gateway namespace for HTTPRoute |
| `litellm-proxy.litellm.modelList` | list | `[]` | Model routing list (see values.yaml for format and examples) |

## Using External Databases

Disable the bundled databases inside litellm-proxy and provide external endpoints:

```yaml
# values-external-db.yaml
litellm-proxy:
  database:
    internal:
      enabled: false
    host: "my-external-postgresql.database.svc.cluster.local"
    port: 5432
    name: "litellm"
    user: "litellm"
    passwordSecretName: "my-postgres-secret"
    passwordSecretKey: "password"
  cache:
    internal:
      enabled: false
    host: "my-external-redis.cache.svc.cluster.local"
    port: 6379
    passwordSecretName: "my-redis-secret"
    passwordSecretKey: "password"
```

```bash
helm install infra ./charts/inference-infrastructure -f values-external-db.yaml
```

### External Cache with Sentinel

For Redis/Valkey clusters with Sentinel:

```yaml
litellm-proxy:
  cache:
    internal:
      enabled: false
    sentinel:
      enabled: true
      host: "my-sentinel.cache.svc.cluster.local"
      port: 26379
      masterName: "mymaster"
    passwordSecretName: "my-redis-secret"
    passwordSecretKey: "password"
```

## Custom Release Names

The Gateway name follows the convention `<release-name>-gateway`. This name is referenced by the `inference-stack` chart's EnvoyExtensionPolicy.

If using a release name other than `infra`, update `inference-stack` accordingly:

```bash
# Example: release name "platform" instead of "infra"
helm install platform ./charts/inference-infrastructure

# Then tell inference-stack about the gateway name
helm install stack ./charts/inference-stack \
  --set inference-gateway.extensionPolicy.targetName=platform-gateway
```

When using internal databases with a non-default release name, LiteLLM's bundled PostgreSQL and Valkey services will automatically use the new release name prefix -- no manual overrides are needed.

## Gateway Configuration

### HTTP and HTTPS Listeners

The Gateway supports HTTP, HTTPS, or both listeners simultaneously.

**HTTP only (default):**

```yaml
gateway:
  listeners:
    http:
      enabled: true
    https:
      enabled: false
```

**HTTPS with cert-manager:**

```yaml
gateway:
  listeners:
    http:
      enabled: true   # Keep for HTTP->HTTPS redirect if desired
    https:
      enabled: true
      hostname: "llm.example.com"
      certificateRef: "llm-gateway-tls"
      certManager:
        enabled: true
        clusterIssuer: "letsencrypt-prod"
```

When `certManager.enabled` is true, the Gateway is annotated with `cert-manager.io/cluster-issuer` so cert-manager automatically provisions and manages the TLS certificate.

### Service Type and Annotations

Control how the Envoy proxy is exposed:

```yaml
gateway:
  service:
    type: LoadBalancer  # or ClusterIP, NodePort
    annotations:
      # AWS ALB example
      service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
      # GCP example
      # cloud.google.com/load-balancer-type: "External"
```

## Troubleshooting

### Gateway Not Programmed

```bash
# Check Gateway status
kubectl get gateway
kubectl describe gateway infra-gateway

# Check GatewayClass
kubectl get gatewayclass llm-gateway

# Check Envoy Gateway controller logs
kubectl logs -l app.kubernetes.io/name=envoy-gateway -n envoy-gateway-system
```

Common issues:
- **GatewayClass not accepted**: Envoy Gateway controller not running. Ensure `inference-operators` was installed first.
- **No address assigned**: Check the Envoy proxy Service and cloud load balancer provisioning.

### LiteLLM Not Starting

```bash
# Check LiteLLM logs
kubectl logs -l app.kubernetes.io/name=litellm-proxy

# Check database connectivity from LiteLLM pod
kubectl exec -it deploy/infra-litellm-proxy -- \
  nc -zv infra-postgresql-pooler-rw 5432
```

Common issues:
- **Connection refused**: PostgreSQL pooler not ready yet. Wait for the CNPG cluster to fully initialize.
- **Authentication failed**: Check that secret names match between PostgreSQL and LiteLLM config.

### CNPG Cluster Not Ready

```bash
# Check cluster status
kubectl describe cluster infra-postgresql

# Check CNPG operator logs
kubectl logs -l app.kubernetes.io/name=cloudnative-pg

# Check PostgreSQL instance logs
kubectl logs -l cnpg.io/cluster=infra-postgresql
```

Common issues:
- **Pending PVC**: Check that a storage class exists and has available capacity.
- **Operator not running**: Ensure `inference-crds` and `inference-operators` were installed first.

### Service Discovery Issues

Verify services exist with expected names:

```bash
# Check infrastructure services
kubectl get svc | grep -E "(postgresql|valkey|gateway)"
```
