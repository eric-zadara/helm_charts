# Inference Operators

Umbrella chart that installs all operators and CRDs for the LLM inference platform in a single command.

## Overview

This chart bundles the CNPG operator and four CRD charts into one installation:

| Component | Type | Description |
|-----------|------|-------------|
| cloudnative-pg | Operator + CRDs | PostgreSQL cluster management via CNPG |
| gateway-api | CRDs | Kubernetes Gateway API for ingress |
| knative-serving-crds | CRDs | Serverless workload orchestration |
| kserve-crds | CRDs | ML model serving lifecycle |
| inference-extension-crds | CRDs | KV-cache aware routing |

## Prerequisites

- Kubernetes 1.25+
- Helm 3.8+

No other operators or controllers need to be installed before this chart. This is the foundation layer that provides operators and CRDs for subsequent components.

## Quick Start

```bash
# Install operators and CRDs
helm install operators ./charts/inference-operators

# Verify CNPG operator is running
kubectl get pods -l app.kubernetes.io/name=cloudnative-pg

# Verify CRDs installed
kubectl get crd | grep -E 'gateway|knative|kserve|inference|cnpg'
```

## CloudNativePG Operator

The CNPG operator enables PostgreSQL cluster deployment via the `Cluster` CRD. It's required before installing inference-infrastructure with database components.

The operator installs:
- CNPG controller deployment
- Cluster, Pooler, Backup, and related CRDs
- RBAC resources for cluster management

### Disable CNPG Operator

If CNPG is already installed in your cluster:

```yaml
cloudnative-pg:
  enabled: false
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `cloudnative-pg.enabled` | bool | `true` | Install CNPG operator and CRDs |
| `gateway-api.enabled` | bool | `true` | Install Gateway API CRDs |
| `knative-serving-crds.enabled` | bool | `true` | Install Knative Serving CRDs |
| `kserve-crds.enabled` | bool | `true` | Install KServe CRDs |
| `inference-extension-crds.enabled` | bool | `true` | Install Inference Extension CRDs |

## Selective Installation

Disable specific components if they're already installed:

```yaml
# Skip Gateway API if already present
gateway-api:
  enabled: false

# Skip CNPG if operator already deployed
cloudnative-pg:
  enabled: false
```

```bash
helm install operators ./charts/inference-operators -f custom-values.yaml
```

## Upgrade Notes

CRDs are typically additive - new fields and resources are added, but existing ones remain stable. Upgrading this chart updates both the CNPG operator and CRD definitions without affecting running workloads.

```bash
helm upgrade operators ./charts/inference-operators
```

## Uninstallation

```bash
helm uninstall operators
```

Note: Helm does not delete CRDs on uninstall by design. This prevents accidental deletion of all custom resources. To fully remove CRDs:

```bash
# DANGER: This deletes all resources of these types
kubectl delete crd -l app.kubernetes.io/managed-by=Helm
```

## Troubleshooting

**CRDs already exist:**

If CRDs are already installed (e.g., from operator helm charts), disable the corresponding subchart:

```yaml
gateway-api:
  enabled: false  # Already installed by envoy-gateway
```

**CNPG operator not starting:**

```bash
# Check operator pods
kubectl get pods -l app.kubernetes.io/name=cloudnative-pg

# Check operator logs
kubectl logs -l app.kubernetes.io/name=cloudnative-pg
```

**Helm dependency issues:**

```bash
# Rebuild dependencies
helm dependency update ./charts/inference-operators
helm dependency build ./charts/inference-operators
```

**Verify specific CRDs:**

```bash
# CNPG
kubectl get crd clusters.postgresql.cnpg.io

# Gateway API
kubectl get crd gateways.gateway.networking.k8s.io

# Knative
kubectl get crd services.serving.knative.dev

# KServe
kubectl get crd inferenceservices.serving.kserve.io

# Inference Extension
kubectl get crd inferencepools.inference.networking.x-k8s.io
```
