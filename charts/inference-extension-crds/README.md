# Gateway API Inference Extension CRDs

Helm chart for installing Gateway API Inference Extension Custom Resource Definitions.

## Overview

This chart installs the Inference Extension CRDs required for KV-cache aware routing:

**Core CRDs:**
- **InferencePool** (inference.networking.k8s.io) - Defines a pool of model serving endpoints
- **InferencePool** (inference.networking.x-k8s.io) - Experimental API group

**Routing CRDs:**
- **InferenceModelRewrite** - URL rewriting rules for model endpoints
- **InferenceObjective** - Priority and SLO definitions for inference requests
- **InferencePoolImport** - Cross-namespace pool references

**Version:** 1.3.0 (pinned from upstream Gateway API Inference Extension release)
**Source:** https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/v1.3.0/manifests.yaml

## Prerequisites

- Kubernetes 1.25+
- Helm 3.10+
- Cluster admin permissions (for CRD installation)
- Gateway API CRDs installed (use gateway-api chart)

## Installation

```bash
helm install inference-extension-crds ./charts/inference-extension-crds
```

Verify installation:

```bash
kubectl get crd | grep inference
```

Expected output:

```
inferencemodelrewrites.inference.networking.x-k8s.io
inferenceobjectives.inference.networking.x-k8s.io
inferencepoolimports.inference.networking.x-k8s.io
inferencepools.inference.networking.k8s.io
inferencepools.inference.networking.x-k8s.io
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `skipIfExists` | bool | `false` | Skip CRD installation if already exists |
| `keepOnUninstall` | bool | `true` | Preserve CRDs on helm uninstall (prevents data loss) |

## Upgrading

CRDs are upgraded in-place when the chart version changes. Existing InferencePool resources are preserved.

```bash
helm upgrade inference-extension-crds ./charts/inference-extension-crds
```

## Uninstalling

**Warning:** Uninstalling with `keepOnUninstall: false` will delete all InferencePool resources.

```bash
# Safe uninstall (keeps CRDs)
helm uninstall inference-extension-crds

# Force CRD deletion (DANGER: deletes all InferencePool resources)
helm uninstall inference-extension-crds --set keepOnUninstall=false
```

## Troubleshooting

**CRDs not appearing:**

```bash
kubectl get crd | grep inference
kubectl describe crd inferencepools.inference.networking.k8s.io
```

**InferencePool not reconciling:**

```bash
kubectl get inferencepool -A
kubectl describe inferencepool <name> -n <namespace>
```

**EPP not discovering endpoints:**

```bash
kubectl get endpointslices -n <namespace> -l inference.networking.k8s.io/pool-name=<pool-name>
```

**Version verification:**

```bash
kubectl get crd inferencepools.inference.networking.k8s.io -o jsonpath='{.spec.versions[*].name}'
```
