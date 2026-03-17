# Inference Operators

Umbrella chart that installs all operators required by the LLM inference platform in a single command.

## Overview

This chart bundles five operator subchart dependencies:

| Component | Version | Type | Default | Description |
|-----------|---------|------|---------|-------------|
| cert-manager | v1.19.3 | Operator | Enabled | TLS certificate management (issuers, certificates, ACME) |
| cloudnative-pg | 0.27.1 | Operator | Enabled | PostgreSQL cluster management via CNPG |
| knative-operator | v1.21.0 | Operator | **Disabled** | Manages Knative Serving installation (only needed for Knative deployment mode) |
| envoy-gateway (gateway-helm) | v1.7.0 | Operator | Enabled | Envoy-based Gateway API controller |
| gpu-operator | v25.10.1 | Operator | Enabled | NVIDIA GPU device plugin, runtime, and monitoring |

By default, this chart installs operators for **Standard mode** (no Knative). If you need Knative deployment mode (scale-to-zero), enable `knative-operator` -- see [Knative Operator](#knative-operator-optional--knative-mode) below.

CRDs are **not** bundled in this chart. They are installed separately by the prerequisite chart `inference-crds`.

## Prerequisites

- Kubernetes 1.25+
- Helm 3.8+
- **`inference-crds` chart must be installed first.** This chart provides all CRDs (Gateway API, cert-manager, KServe, Knative, Inference Extension, CNPG) that the operators in this chart depend on. Without it, operator deployments will fail because the CRDs they watch do not exist.

## Quick Start

```bash
# 1. Install CRDs (prerequisite)
helm install inference-crds ./charts/inference-crds

# 2. Install operators (Standard mode -- Knative disabled by default)
helm install operators ./charts/inference-operators

# 3. Verify operators are running
kubectl get pods -l app.kubernetes.io/name=cert-manager
kubectl get pods -l app.kubernetes.io/name=cloudnative-pg
kubectl get pods -l app.kubernetes.io/name=envoy-gateway
kubectl get pods -l app.kubernetes.io/name=gpu-operator
```

### Optional: Enable Knative mode

To use Knative deployment mode (scale-to-zero), enable the Knative Operator:

```bash
helm install operators ./charts/inference-operators \
  --set knative-operator.enabled=true

# Verify the Knative Operator is running
kubectl get pods -l app.kubernetes.io/name=knative-operator
```

When Knative mode is enabled, the `inference-infrastructure` chart creates the KnativeServing CR that the Knative Operator reconciles to deploy Knative Serving components.

## cert-manager

The cert-manager operator automates TLS certificate issuance and renewal. It watches `Certificate`, `Issuer`, and `ClusterIssuer` resources and provisions certificates from various sources (Let's Encrypt, self-signed, Vault, etc.).

CRD installation is disabled (`crds.enabled: false`) because CRDs are provided by `inference-crds`.

### Disable cert-manager

If cert-manager is already installed in your cluster:

```yaml
cert-manager:
  enabled: false
```

## CloudNativePG Operator

The CNPG operator enables PostgreSQL cluster deployment via the `Cluster` CRD. It is required before installing infrastructure components that need PostgreSQL databases.

The operator installs:
- CNPG controller deployment
- RBAC resources for cluster management

### Disable CNPG Operator

If CNPG is already installed in your cluster:

```yaml
cloudnative-pg:
  enabled: false
```

## Knative Operator (Optional -- Knative Mode)

The Knative Operator is **disabled by default**. It is only required when using Knative deployment mode in `inference-infrastructure` for scale-to-zero capability.

In Standard mode (the default), inference services run as regular Kubernetes Deployments and do not need Knative. Enable the Knative Operator only if you want Knative-managed services with scale-to-zero.

### Enable Knative Operator

```yaml
knative-operator:
  enabled: true
```

When enabled, the operator watches for KnativeServing custom resources. The `inference-infrastructure` chart creates the KnativeServing CR that the operator reconciles to deploy the full Knative Serving stack:

- **Activator** -- buffers requests during scale-from-zero
- **Autoscaler** -- scales pods based on concurrency/RPS metrics
- **Controller** -- reconciles Knative Service, Configuration, Revision, Route resources
- **Webhook** -- validates and defaults Knative resources
- **Kourier** ingress controller (ClusterIP mode -- Envoy Gateway handles external traffic)

All Knative Serving components deploy to the `knative-serving` namespace.

### KnativeServing Configuration

The KnativeServing CR is created by `inference-infrastructure` (not this chart). When Knative mode is enabled, it includes tuned defaults for LLM inference workloads:

| Setting | Value | Reason |
|---------|-------|--------|
| `spec.version` | `1.21` | Matches Knative Operator v1.21.0 |
| Kourier ingress (ClusterIP) | enabled | Internal-only routing; Envoy Gateway handles external traffic |
| `progress-deadline` | `1200s` | Extended from default 600s for slow GPU model loading |
| `enable-scale-to-zero` | `true` | Free GPU resources when idle |
| `scale-to-zero-grace-period` | `30s` | Grace period before removing last pod |
| `scale-down-delay` | `300s` | Extended to avoid thrashing on bursty LLM traffic |
| `podspec-terminationGracePeriodSeconds` | Enabled | Allows graceful model unloading |
| `podspec-tolerations` | Enabled | Allows GPU node scheduling tolerations |
| `podspec-nodeselector` | Enabled | Allows GPU type selection via nodeSelector |
| `podspec-affinity` | Enabled | Allows advanced scheduling rules |

## Envoy Gateway

Envoy Gateway is a Gateway API implementation backed by Envoy Proxy. It watches `Gateway`, `HTTPRoute`, and related resources and provisions Envoy data-plane instances to handle traffic.

### Disable Envoy Gateway

If a Gateway API controller is already installed in your cluster:

```yaml
envoy-gateway:
  enabled: false
```

## NVIDIA GPU Operator

The GPU Operator automates the management of NVIDIA GPU resources on Kubernetes nodes. It deploys:
- GPU device plugin (exposes `nvidia.com/gpu` resources to the scheduler)
- Container runtime hooks (nvidia-container-toolkit)
- GPU Feature Discovery (node labels for GPU type, memory, driver version)
- DCGM monitoring exporter

By default, driver installation is disabled (`driver.enabled: false`) because GPU cloud VMs typically have NVIDIA drivers pre-installed.

### Disable GPU Operator

If the GPU Operator is already installed, or you are running on a cluster without GPUs (e.g., development/CI):

```yaml
gpu-operator:
  enabled: false
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `cert-manager.enabled` | bool | `true` | Install cert-manager operator |
| `cert-manager.crds.enabled` | bool | `false` | CRD installation (disabled; use inference-crds) |
| `cloudnative-pg.enabled` | bool | `true` | Install CNPG operator |
| `knative-operator.enabled` | bool | `false` | Install Knative Operator (only needed for Knative deployment mode) |
| `envoy-gateway.enabled` | bool | `true` | Install Envoy Gateway controller |
| `gpu-operator.enabled` | bool | `true` | Install NVIDIA GPU Operator |
| `gpu-operator.driver.enabled` | bool | `false` | Install NVIDIA drivers (disabled for pre-installed drivers) |

## Selective Installation

Disable or enable specific components based on your cluster:

```yaml
# Skip cert-manager if already present
cert-manager:
  enabled: false

# Skip CNPG if operator already deployed
cloudnative-pg:
  enabled: false

# Enable Knative Operator for scale-to-zero (disabled by default)
knative-operator:
  enabled: true

# Skip Envoy Gateway if a Gateway API controller is already deployed
envoy-gateway:
  enabled: false

# Skip GPU Operator (e.g., no GPUs in cluster)
gpu-operator:
  enabled: false
```

```bash
helm install operators ./charts/inference-operators -f custom-values.yaml
```

## Upgrade Notes

Upgrading this chart updates operators (cert-manager, CNPG, Envoy Gateway, GPU Operator, and optionally Knative Operator) without affecting running workloads. CRDs are managed separately by `inference-crds` and should be upgraded there.

Knative Operator is disabled by default since v0.8.0. If you were previously relying on Knative mode, ensure `knative-operator.enabled: true` is set in your values.

```bash
helm upgrade operators ./charts/inference-operators
```

## Uninstallation

```bash
helm uninstall operators
```

Note: Helm does not delete CRDs on uninstall by design. CRDs are managed by the `inference-crds` chart and should be removed there if needed.

## Troubleshooting

**Operators fail to start with missing CRD errors:**

Ensure the `inference-crds` chart is installed before this chart:

```bash
helm list -A | grep inference-crds
# If not found:
helm install inference-crds ./charts/inference-crds
```

**cert-manager not starting:**

```bash
kubectl get pods -l app.kubernetes.io/name=cert-manager
kubectl logs -l app.kubernetes.io/name=cert-manager
```

**CNPG operator not starting:**

```bash
kubectl get pods -l app.kubernetes.io/name=cloudnative-pg
kubectl logs -l app.kubernetes.io/name=cloudnative-pg
```

**Envoy Gateway not starting:**

```bash
kubectl get pods -l app.kubernetes.io/name=envoy-gateway
kubectl logs -l app.kubernetes.io/name=envoy-gateway
```

**GPU Operator not starting:**

```bash
kubectl get pods -l app.kubernetes.io/name=gpu-operator
kubectl logs -l app.kubernetes.io/name=gpu-operator

# Verify GPU nodes are labeled
kubectl get nodes -l nvidia.com/gpu.present=true
```

**Helm dependency issues:**

```bash
helm dependency update ./charts/inference-operators
helm dependency build ./charts/inference-operators
```

### Knative Mode Only

**Knative Operator not starting:**

```bash
kubectl get pods -l app.kubernetes.io/name=knative-operator
kubectl logs -l app.kubernetes.io/name=knative-operator
```

**KnativeServing not becoming ready:**

The KnativeServing CR is created by `inference-infrastructure`, not this chart. Check there first:

```bash
# Check the KnativeServing CR status
kubectl get knativeserving -n knative-serving -o yaml

# Check Knative Operator logs (it reconciles the CR)
kubectl logs -l app.kubernetes.io/name=knative-operator

# Check Knative Serving component pods
kubectl get pods -n knative-serving
```
