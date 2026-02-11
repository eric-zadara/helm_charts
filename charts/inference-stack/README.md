# Inference Stack

Umbrella chart that installs the model serving layer for the LLM inference platform.

## Overview

This chart bundles model serving components into one installation:

| Component | Description | Purpose |
|-----------|-------------|---------|
| model-serving | vLLM, llama.cpp, Ollama ServingRuntimes | Multi-runtime model serving |
| inference-gateway | EPP (Endpoint Picker) + EnvoyExtensionPolicy | KV-cache aware routing |

## Architecture

By default, the internal Gateway is **disabled** (`inference-gateway.gateway.enabled: false`).
EPP attaches to the public Gateway from `inference-infrastructure` via an EnvoyExtensionPolicy:

```
                        External Traffic
                              |
                              v
                    +-------------------+
                    |  Envoy Gateway    |  (from inference-infrastructure)
                    |  (public Gateway) |
                    +--------+----------+
                             |
                    +--------v----------+
                    | EnvoyExtension    |
                    | Policy            |  (wires EPP into Envoy's request path)
                    +--------+----------+
                             |
                    +--------v----------+
                    |       EPP         |  (KV-cache aware routing)
                    +--------+----------+
                             |
            +----------------+----------------+
            |                |                |
            v                v                v
    +-------------+   +-------------+   +-------------+
    |   vLLM      |   | llama.cpp   |   |   Ollama    |
    | (GPU pods)  |   | (CPU pods)  |   | (GPU/CPU)   |
    +-------------+   +-------------+   +-------------+
       (model-serving InferenceServices)
```

**Optional**: If you enable `inference-gateway.gateway.enabled: true`, a dedicated internal
Gateway is created and EPP attaches to that instead. This adds a second load-balancer hop
(public LB -> internal LB -> model pods) but provides an independent failure domain.

## Prerequisites

- Kubernetes 1.25+
- Helm 3.8+
- inference-operators chart installed (CRDs)
- inference-infrastructure chart installed (database, networking, public Gateway)

## Quick Start

```bash
# Install stack (defaults wire to inference-infrastructure's Gateway)
helm install inference-stack ./charts/inference-stack \
  --namespace llm-platform

# Verify deployment
kubectl get clusterservingruntimes  # vLLM, llama.cpp, Ollama runtimes
kubectl get deployment -n llm-platform -l app.kubernetes.io/name=inference-gateway
```

## Cross-Chart Wiring

The `inference-gateway.extensionPolicy.targetName` value connects this chart to the
public Gateway created by `inference-infrastructure`. It defaults to
`"inference-infrastructure-gateway"`, which assumes the infrastructure chart was installed
with release name `inference-infrastructure`.

If you installed `inference-infrastructure` with a different release name, update
`targetName` to match:

```bash
# Example: infrastructure installed as "infra"
helm install inference-stack ./charts/inference-stack \
  --namespace llm-platform \
  --set inference-gateway.extensionPolicy.targetName=infra-gateway
```

The inference-stack also creates services with predictable names:

| Value Pattern | Example (stack release) | Purpose |
|--------------|-------------------------|---------|
| `<stackRelease>-inference-gateway-epp` | `inference-stack-inference-gateway-epp` | EPP service |

## Model Deployment Workflow

Deploying a model requires updates to **both** inference-stack and inference-infrastructure.

### 1. Install Base Stack (ServingRuntimes + EPP)

```bash
helm install inference-stack ./charts/inference-stack \
  --namespace llm-platform
```

### 2. Deploy a Model

Create a values file that enables the InferenceService, InferencePool, and sets the EPP pool name:

```yaml
# my-model-values.yaml
model-serving:
  inferenceService:
    enabled: true
    name: "qwen25-1-5b"
    storageUri: "hf://Qwen/Qwen2.5-1.5B-Instruct"
    gpu: 1
    tensorParallelSize: 1
    minReplicas: 1
    maxReplicas: 3

  inferencePool:
    enabled: true

inference-gateway:
  epp:
    poolName: "qwen25-1-5b"  # Must match inferenceService.name
```

```bash
helm upgrade inference-stack ./charts/inference-stack \
  --namespace llm-platform \
  -f my-model-values.yaml
```

### 3. Configure LiteLLM Routing

Add the model to the LiteLLM routing table in inference-infrastructure:

```yaml
# litellm-values.yaml
litellm-proxy:
  litellm:
    modelList:
      - modelName: qwen25-1-5b
        litellmParams:
          model: openai/qwen25-1-5b
          apiBase: http://qwen25-1-5b-predictor.llm-platform.svc.cluster.local/openai/v1
          apiKey: no-key-needed
```

```bash
helm upgrade inference-infrastructure ./charts/inference-infrastructure \
  --namespace llm-platform \
  -f litellm-values.yaml
```

## Values

### Model Serving

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `model-serving.enabled` | bool | `true` | Enable model-serving subchart |
| `model-serving.servingRuntime.enabled` | bool | `true` | Install vLLM ClusterServingRuntime |
| `model-serving.llamacppRuntime.enabled` | bool | `true` | Install llama.cpp ClusterServingRuntime |
| `model-serving.ollamaRuntime.enabled` | bool | `true` | Install Ollama ClusterServingRuntime |
| `model-serving.inferenceService.enabled` | bool | `false` | Deploy vLLM InferenceService |
| `model-serving.inferencePool.enabled` | bool | `false` | Create InferencePool for EPP routing |

### Inference Gateway

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `inference-gateway.enabled` | bool | `true` | Enable inference-gateway subchart |
| `inference-gateway.epp.replicas` | int | `2` | EPP replica count |
| `inference-gateway.epp.poolName` | string | `""` | InferencePool name for EPP to manage |
| `inference-gateway.gateway.enabled` | bool | `false` | Create internal Gateway (disabled by default; EPP uses public Gateway via ExtensionPolicy) |
| `inference-gateway.extensionPolicy.enabled` | bool | `true` | Create EnvoyExtensionPolicy to wire EPP into Envoy |
| `inference-gateway.extensionPolicy.targetName` | string | `"inference-infrastructure-gateway"` | Gateway name to attach EPP to (must match the Gateway from inference-infrastructure) |

## Multiple Model Deployments

EPP is one-pool-per-instance. For multiple models with independent KV-cache routing,
deploy separate releases:

```bash
# Model 1: Llama 70B (GPU)
helm install llama-stack ./charts/inference-stack \
  --namespace llm-platform \
  -f llama-values.yaml

# Model 2: Qwen 7B (CPU via llama.cpp)
helm install qwen-stack ./charts/inference-stack \
  --namespace llm-platform \
  -f qwen-values.yaml
```

Each release creates its own EPP instance and EnvoyExtensionPolicy, enabling
model-specific routing policies through the shared public Gateway.

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

# Check EnvoyExtensionPolicy targets the correct Gateway
kubectl get envoyextensionpolicy -n llm-platform -o yaml
```

**Model pods not starting:**

```bash
# Check InferenceService status
kubectl describe inferenceservice my-model -n llm-platform

# Check Knative revision
kubectl get revision -n llm-platform
kubectl describe revision -n llm-platform -l serving.kserve.io/inferenceservice=my-model
```
