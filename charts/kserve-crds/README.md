# KServe CRDs

Helm chart for installing KServe Custom Resource Definitions for model serving.

## Overview

This chart installs the KServe CRDs required for ML model serving:

**Core CRDs:**
- **InferenceService** - Primary resource for deploying ML models with autoscaling
- **ServingRuntime** - Namespace-scoped runtime configuration (vLLM, llama.cpp, etc.)
- **ClusterServingRuntime** - Cluster-wide runtime configuration
- **InferenceGraph** - Multi-model inference pipelines

**LLM-specific CRDs:**
- **LLMInferenceService** - LLM-optimized inference configuration
- **LLMInferenceServiceConfig** - LLM inference defaults

**Model Caching CRDs:**
- **LocalModelCache** - Local model caching configuration
- **LocalModelNode** - Node-level model cache status
- **LocalModelNodeGroup** - Group of nodes with cached models

**Storage CRDs:**
- **ClusterStorageContainer** - Storage container configuration

**Legacy CRDs:**
- **TrainedModel** - Trained model metadata (deprecated)

**Version:** 0.16.0 (pinned from upstream KServe release)
**Source:** https://github.com/kserve/kserve/releases/download/v0.16.0/kserve.yaml

## Prerequisites

- Kubernetes 1.25+
- Helm 3.10+
- Cluster admin permissions (for CRD installation)

## Installation

```bash
helm install kserve-crds ./charts/kserve-crds
```

Verify installation:

```bash
kubectl get crd | grep serving.kserve.io
```

Expected output:

```
clusterservingruntimes.serving.kserve.io
clusterstoragecontainers.serving.kserve.io
inferencegraphs.serving.kserve.io
inferenceservices.serving.kserve.io
llminferenceserviceconfigs.serving.kserve.io
llminferenceservices.serving.kserve.io
localmodelcaches.serving.kserve.io
localmodelnodegroups.serving.kserve.io
localmodelnodes.serving.kserve.io
servingruntimes.serving.kserve.io
trainedmodels.serving.kserve.io
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `skipIfExists` | bool | `false` | Skip CRD installation if already exists |
| `keepOnUninstall` | bool | `true` | Preserve CRDs on helm uninstall (prevents data loss) |

## Upgrading

CRDs are upgraded in-place when the chart version changes. Existing InferenceService resources are preserved.

```bash
helm upgrade kserve-crds ./charts/kserve-crds
```

## Uninstalling

**Warning:** Uninstalling with `keepOnUninstall: false` will delete all InferenceService and ServingRuntime resources.

```bash
# Safe uninstall (keeps CRDs)
helm uninstall kserve-crds

# Force CRD deletion (DANGER: deletes all InferenceService resources)
helm uninstall kserve-crds --set keepOnUninstall=false
```

## Troubleshooting

**CRDs not appearing:**

```bash
kubectl get crd | grep kserve
kubectl describe crd inferenceservices.serving.kserve.io
```

**InferenceService not reconciling:**

```bash
kubectl get inferenceservice -A
kubectl describe inferenceservice <name> -n <namespace>
```

**ServingRuntime not found:**

```bash
kubectl get clusterservingruntime
kubectl get servingruntime -n <namespace>
```

**Storage initializer failures:**

```bash
kubectl logs -l serving.kserve.io/inferenceservice=<name> -c storage-initializer
```
