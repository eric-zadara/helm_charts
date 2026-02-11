# Inference Operators

Umbrella chart that installs all operators required by the LLM inference platform in a single command.

## Overview

This chart bundles six operator subchart dependencies:

| Component | Version | Type | Description |
|-----------|---------|------|-------------|
| cert-manager | v1.19.3 | Operator | TLS certificate management (issuers, certificates, ACME) |
| cloudnative-pg | 0.27.1 | Operator | PostgreSQL cluster management via CNPG |
| kserve | v0.16.0 | Operator | KServe controller for InferenceService/ClusterServingRuntime reconciliation |
| knative-operator | v1.21.0 | Operator | Manages Knative Serving installation via KnativeServing CR |
| envoy-gateway (gateway-helm) | v1.7.0 | Operator | Envoy-based Gateway API controller |
| gpu-operator | v25.10.1 | Operator | NVIDIA GPU device plugin, runtime, and monitoring |

The chart also creates a **KnativeServing** custom resource in the `knative-serving` namespace, which the Knative Operator reconciles to deploy Knative Serving components (activator, autoscaler, controller, webhook).

CRDs are **not** bundled in this chart. They are installed separately by the prerequisite chart `inference-crds`.

## Prerequisites

- Kubernetes 1.25+
- Helm 3.8+
- **`inference-crds` chart must be installed first.** This chart provides all CRDs (Gateway API, cert-manager, KServe, Knative, Inference Extension, CNPG) that the operators in this chart depend on. Without it, operator deployments will fail because the CRDs they watch do not exist.

## Quick Start

```bash
# 1. Install CRDs (prerequisite)
helm install inference-crds ./charts/inference-crds

# 2. Install operators
helm install operators ./charts/inference-operators

# 3. Verify operators are running
kubectl get pods -l app.kubernetes.io/name=cert-manager
kubectl get pods -l app.kubernetes.io/name=cloudnative-pg
kubectl get pods -l control-plane=kserve-controller-manager
kubectl get pods -l app.kubernetes.io/name=knative-operator
kubectl get pods -l app.kubernetes.io/name=envoy-gateway
kubectl get pods -l app.kubernetes.io/name=gpu-operator

# 4. Verify KnativeServing CR is created
kubectl get knativeserving -n knative-serving
```

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

## KServe Controller

The KServe controller reconciles `InferenceService` and `ClusterServingRuntime` resources. Without it, these CRDs are accepted by the API server but never acted upon. It is required for the model-serving chart's serving runtimes and inference services to function.

The operator installs:
- KServe controller-manager deployment
- KServe webhook for validation and defaulting
- `inferenceservice-config` ConfigMap with deployment mode and runtime configuration

### Configuration

The controller is configured with:
- **Knative deployment mode** -- InferenceServices create Knative Services (requires Knative Serving)
- **All built-in runtimes disabled** -- This project provides its own ClusterServingRuntimes via the model-serving chart (vLLM, llama.cpp, Ollama) rather than using KServe's built-in runtimes (TensorFlow, sklearn, etc.)
- **Local model support disabled** -- Not needed for this project

### Disable KServe Controller

If KServe is already installed in your cluster:

```yaml
kserve:
  enabled: false
```

## Knative Operator and KnativeServing CR

The Knative Operator manages Knative Serving (and Eventing) installations declaratively via custom resources. This chart installs the operator and then creates a **KnativeServing** CR that the operator reconciles to deploy the full Knative Serving stack:

- **Activator** -- buffers requests during scale-from-zero
- **Autoscaler** -- scales pods based on concurrency/RPS metrics
- **Controller** -- reconciles Knative Service, Configuration, Revision, Route resources
- **Webhook** -- validates and defaults Knative resources
- **Kourier** ingress controller (ClusterIP mode -- Envoy Gateway handles external traffic)

All Knative Serving components deploy to the `knative-serving` namespace.

### Why the KnativeServing CR is co-located with the operator

The KnativeServing CR is created in this chart (alongside the Knative Operator and KServe) rather than in a downstream chart because **KServe caches a terminal error if Knative Serving is not available at first reconciliation**. If KServe starts before Knative Serving is ready, it marks the failure as permanent and never retries. By co-locating the KnativeServing CR here, Knative Serving is deployed as part of the same release and is ready before any downstream chart creates InferenceServices.

### KnativeServing Configuration

The KnativeServing CR includes tuned defaults for LLM inference workloads:

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

### Disable Knative Operator / KnativeServing

```yaml
# Disable the operator entirely
knative-operator:
  enabled: false

# Disable only the KnativeServing CR (keep the operator)
knativeServing:
  enabled: false
```

## Envoy Gateway

Envoy Gateway is a Gateway API implementation backed by Envoy Proxy. It watches `Gateway`, `HTTPRoute`, and related resources and provisions Envoy data-plane instances to handle traffic.

In this platform, Envoy Gateway handles external traffic ingress while Kourier (deployed by KnativeServing) handles internal Knative Service routing.

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
| `kserve.enabled` | bool | `true` | Install KServe controller and webhook |
| `kserve.kserve.controller.deploymentMode` | string | `"Knative"` | KServe deployment mode (Knative or RawDeployment) |
| `kserve.kserve.servingruntime.<name>.disabled` | bool | `true` | Disable individual built-in serving runtimes |
| `kserve.kserve.localmodel.enabled` | bool | `false` | Enable KServe local model support |
| `knative-operator.enabled` | bool | `true` | Install Knative Operator |
| `knativeServing.enabled` | bool | `true` | Create KnativeServing CR |
| `knativeServing.namespace` | string | `"knative-serving"` | Namespace for KnativeServing CR and components |
| `knativeServing.spec` | object | see values.yaml | KnativeServing spec (version, ingress, config maps) |
| `envoy-gateway.enabled` | bool | `true` | Install Envoy Gateway controller |
| `gpu-operator.enabled` | bool | `true` | Install NVIDIA GPU Operator |
| `gpu-operator.driver.enabled` | bool | `false` | Install NVIDIA drivers (disabled for pre-installed drivers) |

## Selective Installation

Disable specific components if they are already installed in your cluster:

```yaml
# Skip cert-manager if already present
cert-manager:
  enabled: false

# Skip CNPG if operator already deployed
cloudnative-pg:
  enabled: false

# Skip KServe if controller already deployed
kserve:
  enabled: false

# Skip Knative Operator if already deployed
knative-operator:
  enabled: false

# Skip KnativeServing CR if Knative Serving is already running
knativeServing:
  enabled: false

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

Upgrading this chart updates operators (cert-manager, CNPG, KServe, Knative Operator, Envoy Gateway, GPU Operator) and the KnativeServing CR without affecting running workloads. CRDs are managed separately by `inference-crds` and should be upgraded there.

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

**KServe controller not starting:**

```bash
kubectl get pods -l control-plane=kserve-controller-manager
kubectl logs -l control-plane=kserve-controller-manager
```

**KnativeServing not becoming ready:**

```bash
# Check the KnativeServing CR status
kubectl get knativeserving -n knative-serving -o yaml

# Check Knative Operator logs (it reconciles the CR)
kubectl logs -l app.kubernetes.io/name=knative-operator

# Check Knative Serving component pods
kubectl get pods -n knative-serving
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
