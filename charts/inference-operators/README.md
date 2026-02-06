# Inference Operators

Umbrella chart that installs all operators and CRDs for the LLM inference platform in a single command.

## Overview

This chart bundles three operators and four CRD charts into one installation:

| Component | Type | Description |
|-----------|------|-------------|
| cloudnative-pg | Operator + CRDs | PostgreSQL cluster management via CNPG |
| kserve | Operator | KServe controller for InferenceService/ClusterServingRuntime reconciliation |
| knative-serving | Operator | Knative Serving core (activator, autoscaler, controller, webhook) |
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

# Verify KServe controller is running
kubectl get pods -l control-plane=kserve-controller-manager

# Verify Knative Serving core is running
kubectl get pods -n knative-serving

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

## KServe Controller

The KServe controller reconciles `InferenceService` and `ClusterServingRuntime` resources. Without it, these CRDs are accepted by the API server but never acted upon. It's required for the model-serving chart's serving runtimes and inference services to function.

The operator installs:
- KServe controller-manager deployment
- KServe webhook for validation and defaulting
- `inferenceservice-config` ConfigMap with deployment mode and runtime configuration

### Configuration

The controller is configured with:
- **Knative deployment mode** -- InferenceServices create Knative Services (requires Knative Serving core)
- **All built-in runtimes disabled** -- This project provides its own ClusterServingRuntimes via the model-serving chart (vLLM, llama.cpp, Ollama) rather than using KServe's built-in runtimes (TensorFlow, sklearn, etc.)

### Disable KServe Controller

If KServe is already installed in your cluster:

```yaml
kserve:
  enabled: false
```

## Knative Serving Core

Knative Serving core deploys the components that reconcile Knative Services, manage revisions, and handle autoscaling. It reads ConfigMaps (config-autoscaler, config-features, config-network) that are created by the networking-layer chart.

The operator installs:
- Activator -- buffers requests during scale-from-zero
- Autoscaler -- scales pods based on concurrency/RPS metrics
- Controller -- reconciles Knative Service, Configuration, Revision, Route resources
- Webhook -- validates and defaults Knative resources

All components deploy to the `knative-serving` namespace.

### Configuration

ConfigMaps for Knative Serving (config-autoscaler, config-features, config-network) are managed by the **networking-layer** chart, not by this chart. This separation allows infrastructure operators to tune autoscaling and networking independently of the operator lifecycle.

### Disable Knative Serving Core

If Knative Serving is already installed in your cluster:

```yaml
knative-serving:
  enabled: false
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `cloudnative-pg.enabled` | bool | `true` | Install CNPG operator and CRDs |
| `kserve.enabled` | bool | `true` | Install KServe controller and webhook |
| `kserve.kserve.controller.deploymentMode` | string | `"Knative"` | KServe deployment mode (Knative or RawDeployment) |
| `kserve.kserve.servingruntime.<name>.disabled` | bool | `true` | Disable individual built-in serving runtimes |
| `kserve.kserve.localmodel.enabled` | bool | `false` | Enable KServe local model support |
| `knative-serving.enabled` | bool | `true` | Install Knative Serving core components |
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

# Skip KServe if controller already deployed
kserve:
  enabled: false

# Skip Knative Serving if already deployed
knative-serving:
  enabled: false
```

```bash
helm install operators ./charts/inference-operators -f custom-values.yaml
```

## Upgrade Notes

CRDs are typically additive - new fields and resources are added, but existing ones remain stable. Upgrading this chart updates operators (CNPG, KServe, Knative Serving) and CRD definitions without affecting running workloads.

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

**KServe controller not starting:**

```bash
# Check controller pods
kubectl get pods -l control-plane=kserve-controller-manager

# Check controller logs
kubectl logs -l control-plane=kserve-controller-manager
```

**Knative Serving not starting:**

```bash
# Check all Knative Serving pods
kubectl get pods -n knative-serving

# Check controller logs
kubectl logs -n knative-serving -l app=controller
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
