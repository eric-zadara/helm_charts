# Inference Stack

Umbrella chart that installs the model serving layer for the LLM inference platform.

## Overview

This chart bundles model serving components into one installation:

| Component | Description | Purpose |
|-----------|-------------|---------|
| model-serving | vLLM, llama.cpp, Ollama ServingRuntimes | Multi-runtime model serving |
| inference-gateway | EPP (Endpoint Picker) + internal Gateway | KV-cache aware routing |

## Architecture

```
                        External Traffic
                              |
                              v
                    +-------------------+
                    |  Envoy Gateway    |  (from inference-infrastructure)
                    +-------------------+
                              |
                              v
                    +-------------------+
                    |  LiteLLM Proxy    |  (from inference-infrastructure)
                    +-------------------+
                              |
                              v
                    +-------------------+
                    | Internal Gateway  |  (inference-gateway)
                    +-------------------+
                              |
                              v
                    +-------------------+
                    |       EPP         |  (KV-cache aware routing)
                    +-------------------+
                              |
            +-----------------+-----------------+
            |                 |                 |
            v                 v                 v
    +-------------+   +-------------+   +-------------+
    |   vLLM      |   | llama.cpp   |   |   Ollama    |
    | (GPU pods)  |   | (CPU pods)  |   | (GPU/CPU)   |
    +-------------+   +-------------+   +-------------+
       (model-serving InferenceServices)
```

## Prerequisites

- Kubernetes 1.25+
- Helm 3.8+
- inference-operators chart installed (CRDs)
- inference-infrastructure chart installed (database, networking)

## Quick Start

```bash
# Install stack with reference to infrastructure
helm install stack ./charts/inference-stack \
  --namespace llm-platform \
  --set infrastructureReleaseName=infra

# Verify deployment
kubectl get clusterservingruntimes  # vLLM, llama.cpp, Ollama runtimes
kubectl get deployment -n llm-platform -l app.kubernetes.io/name=inference-gateway
```

## Cross-Chart Service Discovery

The `infrastructureReleaseName` value enables discovery of services from the infrastructure chart:

| Value Pattern | Example (infra release) | Purpose |
|--------------|-------------------------|---------|
| `<infraRelease>-litellm-proxy` | `infra-litellm-proxy` | API gateway |
| `<infraRelease>-networking-layer-gateway` | `infra-networking-layer-gateway` | External gateway |

The inference-stack also creates services with predictable names:

| Value Pattern | Example (stack release) | Purpose |
|--------------|-------------------------|---------|
| `<stackRelease>-inference-gateway` | `stack-inference-gateway` | Internal gateway |
| `<stackRelease>-inference-gateway-epp` | `stack-inference-gateway-epp` | EPP service |

## Model Deployment Workflow

### 1. Install Base Stack (ServingRuntimes + EPP)

```bash
helm install stack ./charts/inference-stack \
  --namespace llm-platform \
  --set infrastructureReleaseName=infra
```

### 2. Deploy a Model

Create a separate values file for your model:

```yaml
# my-model-values.yaml
model-serving:
  inferenceService:
    enabled: true
    name: "llama-70b"
    storageUri: "hf://meta-llama/Llama-3.3-70B-Instruct"
    gpu: 4
    tensorParallelSize: 4
    minReplicas: 1
    maxReplicas: 4

  inferencePool:
    enabled: true
    eppServiceName: "stack-inference-gateway-epp"

inference-gateway:
  epp:
    poolName: "llama-70b"
```

```bash
helm upgrade stack ./charts/inference-stack \
  --namespace llm-platform \
  -f my-model-values.yaml
```

### 3. Configure LiteLLM Routing

Add the model to LiteLLM configuration:

```yaml
# litellm-values.yaml
litellm-proxy:
  litellm:
    modelList:
      - modelName: "llama-70b"
        litellmParams:
          model: "hosted_vllm/meta-llama/Llama-3.3-70B-Instruct"
          apiBase: "http://stack-inference-gateway.llm-platform.svc.cluster.local"
```

```bash
helm upgrade infra ./charts/inference-infrastructure \
  --namespace llm-platform \
  -f litellm-values.yaml
```

## Values

### Cross-Chart Discovery

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `infrastructureReleaseName` | string | `"infra"` | Release name of inference-infrastructure chart |
| `infrastructureNamespace` | string | `""` | Namespace of infrastructure (defaults to release namespace) |

### Model Serving

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `model-serving.enabled` | bool | `true` | Enable model serving |
| `model-serving.servingRuntime.enabled` | bool | `true` | Install vLLM ClusterServingRuntime |
| `model-serving.llamacppRuntime.enabled` | bool | `true` | Install llama.cpp ClusterServingRuntime |
| `model-serving.ollamaRuntime.enabled` | bool | `true` | Install Ollama ClusterServingRuntime |
| `model-serving.inferenceService.enabled` | bool | `false` | Deploy example InferenceService |
| `model-serving.inferencePool.enabled` | bool | `false` | Create InferencePool for EPP |

### Inference Gateway

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `inference-gateway.enabled` | bool | `true` | Enable inference gateway |
| `inference-gateway.epp.replicas` | int | `2` | EPP replica count |
| `inference-gateway.epp.poolName` | string | `""` | InferencePool name for EPP to manage |
| `inference-gateway.gateway.enabled` | bool | `true` | Create internal Gateway |
| `inference-gateway.extensionPolicy.enabled` | bool | `true` | Wire EPP into Envoy |

## Multiple Model Deployments

For multiple models with different EPP instances, deploy separate releases:

```bash
# Model 1: Llama 70B
helm install llama-stack ./charts/inference-stack \
  --namespace llm-platform \
  --set infrastructureReleaseName=infra \
  -f llama-values.yaml

# Model 2: Qwen 72B
helm install qwen-stack ./charts/inference-stack \
  --namespace llm-platform \
  --set infrastructureReleaseName=infra \
  -f qwen-values.yaml
```

Each release creates its own EPP instance and internal Gateway, enabling model-specific routing policies.

## Troubleshooting

**ClusterServingRuntimes not created:**

```bash
# Check for CRDs
kubectl get crd clusterservingruntimes.serving.kserve.io

# If missing, install inference-operators first
helm install operators ./charts/inference-operators
```

**EPP not routing requests:**

```bash
# Check EPP logs
kubectl logs -n llm-platform -l app.kubernetes.io/name=inference-gateway

# Verify InferencePool exists and matches EPP poolName
kubectl get inferencepool -n llm-platform

# Check EnvoyExtensionPolicy
kubectl get envoyextensionpolicy -n llm-platform
```

**Model pods not starting:**

```bash
# Check InferenceService status
kubectl describe inferenceservice my-model -n llm-platform

# Check Knative revision
kubectl get revision -n llm-platform
kubectl describe revision -n llm-platform -l serving.kserve.io/inferenceservice=my-model
```
