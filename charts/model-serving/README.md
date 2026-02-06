# Model Serving

Helm chart for multi-runtime LLM model serving (vLLM, llama.cpp, Ollama).

## Overview

This chart deploys:

- **ClusterServingRuntimes** - vLLM (GPU), llama.cpp (CPU/GGUF), Ollama (simple)
- **InferenceService** - Optional model deployment templates
- **Supporting resources** - HuggingFace secrets, S3 credentials, PriorityClasses

## Supported Runtimes

| Runtime | Use Case | Model Format | Hardware |
|---------|----------|--------------|----------|
| vLLM | Production GPU inference | SafeTensors/HF | NVIDIA GPU |
| llama.cpp | CPU inference, GGUF models | GGUF | CPU (AVX2) |
| Ollama | Simple deployments, dev | Ollama registry | CPU or GPU |

## Prerequisites

- Kubernetes 1.25+
- KServe CRDs installed (use kserve-crds chart)
- Knative Serving CRDs installed (use knative-serving-crds chart)
- Networking layer deployed (use networking-layer chart)
- GPU nodes with nvidia.com/gpu resources (for vLLM/Ollama GPU)

## Quick Start

```bash
# Deploy runtimes only (no models)
helm install model-serving ./charts/model-serving \
  --namespace llm-platform

# Deploy with a test model
helm install model-serving ./charts/model-serving \
  --namespace llm-platform \
  --set inferenceService.enabled=true \
  --set inferenceService.name=qwen25-7b \
  --set inferenceService.storageUri=hf://Qwen/Qwen2.5-7B-Instruct \
  --set inferenceService.gpu=1
```

Verify:

```bash
kubectl get clusterservingruntime
kubectl get inferenceservice -n llm-platform
```

## Values

### vLLM Runtime

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `servingRuntime.enabled` | bool | `true` | Create vLLM ClusterServingRuntime |
| `servingRuntime.name` | string | `kserve-vllm` | Runtime name |
| `servingRuntime.image` | string | `kserve/huggingfaceserver` | Container image |
| `servingRuntime.tag` | string | `v0.16.0-gpu` | Image tag |
| `servingRuntime.gpuMemoryUtilization` | float | `0.85` | GPU memory fraction |
| `servingRuntime.maxModelLen` | int | `16384` | Max context length |
| `servingRuntime.enablePrefixCaching` | bool | `true` | Enable KV-cache optimization |

### vLLM InferenceService

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `inferenceService.enabled` | bool | `false` | Deploy InferenceService |
| `inferenceService.name` | string | `qwen25-1-5b` | InferenceService name |
| `inferenceService.storageUri` | string | `hf://Qwen/Qwen2.5-1.5B-Instruct` | Model URI |
| `inferenceService.gpu` | int | `1` | Number of GPUs (1-4) |
| `inferenceService.tensorParallelSize` | int | `1` | Tensor parallel size (must match gpu) |
| `inferenceService.minReplicas` | int | `0` | Minimum replicas (0 = scale-to-zero) |
| `inferenceService.maxReplicas` | int | `3` | Maximum replicas |
| `inferenceService.scaleMetric` | string | `concurrency` | Autoscaling metric |
| `inferenceService.scaleTarget` | int | `10` | Autoscaling target |
| `inferenceService.huggingfaceSecret` | string | `""` | HuggingFace secret for gated models |

### llama.cpp Runtime

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `llamacppRuntime.enabled` | bool | `true` | Create llama.cpp ClusterServingRuntime |
| `llamacppRuntime.name` | string | `kserve-llamacpp` | Runtime name |
| `llamacppRuntime.image` | string | `ghcr.io/ggml-org/llama.cpp` | Container image |
| `llamacppRuntime.tag` | string | `server-b7850` | Image tag |
| `llamacppRuntime.threads` | int | `16` | CPU threads for inference |
| `llamacppRuntime.contextWindow` | int | `16384` | Context window per slot |
| `llamacppRuntime.parallelSlots` | int | `4` | Parallel request slots |

### llama.cpp InferenceService

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `llamacppInferenceService.enabled` | bool | `false` | Deploy llama.cpp InferenceService |
| `llamacppInferenceService.name` | string | `qwen25-7b-gguf` | InferenceService name |
| `llamacppInferenceService.storageUri` | string | `s3://models/...` | Model URI (S3 recommended for GGUF) |
| `llamacppInferenceService.serviceAccountName` | string | `""` | ServiceAccount for S3 access |

### Ollama Runtime

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `ollamaRuntime.enabled` | bool | `true` | Create Ollama ClusterServingRuntime |
| `ollamaRuntime.name` | string | `kserve-ollama` | Runtime name |
| `ollamaRuntime.image` | string | `ollama/ollama` | Container image |
| `ollamaRuntime.tag` | string | `0.15.2` | Image tag |
| `ollamaRuntime.numParallel` | int | `4` | Parallel requests |
| `ollamaRuntime.contextLength` | int | `16384` | Context length |
| `ollamaRuntime.flashAttention` | bool | `true` | Enable flash attention |

### Ollama InferenceService

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `ollamaInferenceService.enabled` | bool | `false` | Deploy Ollama InferenceService |
| `ollamaInferenceService.name` | string | `qwen3-4b-ollama` | InferenceService name |
| `ollamaInferenceService.modelTag` | string | `qwen3:4b` | Ollama model tag |
| `ollamaInferenceService.gpu` | int | `0` | Number of GPUs (0 for CPU) |

### S3 Storage Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `s3Storage.enabled` | bool | `false` | Enable S3 credentials |
| `s3Storage.secretName` | string | `s3-model-creds` | Secret name |
| `s3Storage.serviceAccountName` | string | `s3-model-sa` | ServiceAccount name |
| `s3Storage.endpoint` | string | `s3.amazonaws.com` | S3 endpoint |
| `s3Storage.region` | string | `us-east-1` | S3 region |

### HuggingFace Authentication

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `huggingface.secretEnabled` | bool | `false` | Create HF secret |
| `huggingface.secretName` | string | `hf-secret` | Secret name |
| `huggingface.token` | string | `""` | HF token (use external secret management) |

## Deployment Examples

### vLLM with GPU (Llama 70B)

```yaml
inferenceService:
  enabled: true
  name: llama-70b
  storageUri: hf://meta-llama/Llama-3.3-70B-Instruct
  gpu: 4
  tensorParallelSize: 4
  huggingfaceSecret: hf-secret
  autoscaling:
    scaleDownDelay: "10m"  # Longer for large models
```

### llama.cpp with S3 (GGUF)

```yaml
llamacppInferenceService:
  enabled: true
  name: qwen-7b-gguf
  storageUri: s3://models/qwen2.5-7b-instruct-q4_k_m.gguf
  serviceAccountName: s3-model-sa

s3Storage:
  enabled: true
  endpoint: s3.us-east-1.amazonaws.com
  accessKeyId: AKIA...
  secretAccessKey: ...
```

### Ollama CPU

```yaml
ollamaInferenceService:
  enabled: true
  name: qwen3-4b
  modelTag: qwen3:4b
  gpu: 0
  resources:
    requests:
      cpu: "8"
      memory: "8Gi"
```

### Ollama with GPU

```yaml
ollamaInferenceService:
  enabled: true
  name: llama-8b-gpu
  modelTag: llama3.1:8b
  gpu: 1
  tolerations:
    - key: "nvidia.com/gpu"
      operator: "Exists"
      effect: "NoSchedule"
```

## InferencePool Integration

Connect to inference-gateway for KV-cache aware routing:

```yaml
inferencePool:
  enabled: true
  targetPort: 8080
  # eppServiceName auto-computes from release name when empty (default).
  # Override only if your inference-gateway release has a non-standard name:
  # eppServiceName: "my-release-inference-gateway-epp"
  eppServicePort: 9002

inferencePoolRoute:
  enabled: true
  gatewayName: inference-gateway
```

## Troubleshooting

**InferenceService stuck in Unknown:**

```bash
kubectl describe inferenceservice <name> -n llm-platform
kubectl get pods -l serving.kserve.io/inferenceservice=<name> -n llm-platform
kubectl logs -l serving.kserve.io/inferenceservice=<name> -c storage-initializer -n llm-platform
```

**Model download failures:**

```bash
# Check storage initializer logs
kubectl logs -l serving.kserve.io/inferenceservice=<name> -c storage-initializer -n llm-platform

# Check HuggingFace token
kubectl get secret hf-secret -n llm-platform -o yaml
```

**GPU not detected:**

```bash
kubectl get nodes -o json | jq '.items[].status.allocatable["nvidia.com/gpu"]'
kubectl describe node <gpu-node> | grep -A5 "Allocated resources"
```

**OOM during model loading:**

```bash
kubectl describe pod -l serving.kserve.io/inferenceservice=<name> -n llm-platform
# Increase memory limits or reduce gpuMemoryUtilization
```

**ClusterServingRuntime not found:**

```bash
kubectl get clusterservingruntime
kubectl describe clusterservingruntime kserve-vllm
```

**vLLM tensor parallel mismatch:**

```bash
# CRITICAL: tensorParallelSize MUST match gpu count
# Wrong: gpu=4, tensorParallelSize=1
# Correct: gpu=4, tensorParallelSize=4
```
