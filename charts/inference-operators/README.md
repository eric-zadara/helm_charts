# Inference Operators

Umbrella chart that installs all CRDs for the LLM inference platform in a single command.

## Overview

This chart bundles four CRD charts into one installation:

| Component | CRDs Installed | Purpose |
|-----------|----------------|---------|
| gateway-api | HTTPRoute, Gateway, GatewayClass, ReferenceGrant | Kubernetes Gateway API for ingress |
| knative-serving-crds | Service, Configuration, Revision, Route | Serverless workload orchestration |
| kserve-crds | InferenceService, ServingRuntime, ClusterServingRuntime | ML model serving lifecycle |
| inference-extension-crds | InferencePool, InferenceModel | KV-cache aware routing |

## Prerequisites

- Kubernetes 1.25+
- Helm 3.8+

No operators or controllers need to be installed before this chart. This is the foundation layer that provides CRDs for subsequent components.

## Quick Start

```bash
# Install all CRDs
helm install operators ./charts/inference-operators

# Verify CRDs installed
kubectl get crd | grep -E 'gateway|knative|kserve|inference'
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `gateway-api.enabled` | bool | `true` | Install Gateway API CRDs |
| `knative-serving-crds.enabled` | bool | `true` | Install Knative Serving CRDs |
| `kserve-crds.enabled` | bool | `true` | Install KServe CRDs |
| `inference-extension-crds.enabled` | bool | `true` | Install Inference Extension CRDs |

## Selective Installation

Disable specific CRD sets if they're already installed:

```yaml
# Skip Gateway API if already present
gateway-api:
  enabled: false
```

```bash
helm install operators ./charts/inference-operators -f custom-values.yaml
```

## Upgrade Notes

CRDs are typically additive - new fields and resources are added, but existing ones remain stable. Upgrading this chart updates CRD definitions without affecting running workloads.

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

**Helm dependency issues:**

```bash
# Rebuild dependencies
helm dependency update ./charts/inference-operators
helm dependency build ./charts/inference-operators
```

**Verify specific CRDs:**

```bash
# Gateway API
kubectl get crd gateways.gateway.networking.k8s.io

# Knative
kubectl get crd services.serving.knative.dev

# KServe
kubectl get crd inferenceservices.serving.kserve.io

# Inference Extension
kubectl get crd inferencepools.inference.networking.x-k8s.io
```
