# Inference CRDs

Umbrella chart that installs all Custom Resource Definitions required by the LLM inference platform.

## Overview

This chart bundles CRD-only subcharts so that all CustomResourceDefinitions are present before any operators or workloads are deployed. It does not install controllers or runtime components -- only the CRD schemas.

### Included CRD Groups

| Subchart | Version | CRDs Provided |
|----------|---------|---------------|
| `cert-manager-crds` | 0.1.0 | Certificate, Issuer, ClusterIssuer |
| `kserve-crd` | v0.16.0 | InferenceService, ServingRuntime, ClusterServingRuntime |
| `gateway-api` | 0.1.0 | HTTPRoute, Gateway, GatewayClass |
| `inference-extension-crds` | 0.1.0 | InferencePool, InferenceModel |

> **Note:** `gateway-api` is disabled by default. Many clusters already have Gateway API CRDs installed via Traefik, Istio, or the Envoy Gateway operator chart. Enable it only if your cluster has no existing Gateway API CRDs.

## Prerequisites

- Kubernetes 1.25+
- Helm 3.8+

## Quick Start

```bash
# Build subchart dependencies
helm dependency build ./charts/inference-crds

# Install CRDs
helm install inference-crds ./charts/inference-crds \
  --namespace kube-system
```

Verify:

```bash
kubectl get crd | grep -E 'cert-manager|kserve|gateway|inference'
```

## Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `cert-manager-crds.enabled` | bool | `true` | Install cert-manager CRDs |
| `kserve-crd.enabled` | bool | `true` | Install KServe CRDs |
| `gateway-api.enabled` | bool | `false` | Install Gateway API CRDs |
| `inference-extension-crds.enabled` | bool | `true` | Install Inference Extension CRDs |

## Selective Installation

Disable individual CRD groups if they are already present in your cluster:

```yaml
# values-override.yaml
cert-manager-crds:
  enabled: false          # cert-manager already installed

kserve-crd:
  enabled: true

gateway-api:
  enabled: true           # no existing Gateway API CRDs

inference-extension-crds:
  enabled: true
```

```bash
helm install inference-crds ./charts/inference-crds \
  --namespace kube-system \
  -f values-override.yaml
```

## Upgrade Notes

- CRD updates are **additive**. New fields and API versions are added; existing fields are never removed within a minor version.
- Always review CRD changelogs before upgrading in production, as schema changes may affect existing custom resources.

## Uninstallation

```bash
helm uninstall inference-crds --namespace kube-system
```

> **Important:** Helm does not delete CRDs on uninstall. This is intentional -- removing CRDs cascades deletion of all custom resources of that type. To fully remove CRDs after uninstall, delete them manually:
>
> ```bash
> kubectl get crd -o name | grep -E 'cert-manager|kserve|gateway|inference' | xargs kubectl delete
> ```

## Troubleshooting

**CRD already exists (conflict on install):**

Another chart or manual install already created the CRD. Disable the conflicting subchart:

```bash
helm install inference-crds ./charts/inference-crds \
  --set gateway-api.enabled=false
```

**Dependency build fails:**

```bash
# Remove stale lockfile and rebuild
rm -f charts/inference-crds/Chart.lock
helm dependency build ./charts/inference-crds
```

**Operators fail with "no matches for kind" after install:**

The operator was deployed before CRDs were ready. Ensure inference-crds is installed first, then deploy operator charts. Verify CRDs are registered:

```bash
kubectl get crd inferenceservices.serving.kserve.io
kubectl get crd certificates.cert-manager.io
kubectl get crd inferencepools.inference.networking.x-k8s.io
```
