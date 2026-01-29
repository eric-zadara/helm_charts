# Inference Gateway

Helm chart for KV-cache aware routing via Gateway API Inference Extension (EPP).

## Overview

The Inference Gateway provides intelligent routing for LLM inference:

- **KV-cache affinity** - Routes similar prompts to the same pod for cache reuse
- **Load balancing** - Considers queue depth and KV-cache utilization
- **Priority handling** - Respects request priority levels

## Architecture

```
LiteLLM Proxy
      │
      ▼
┌─────────────────────────────────┐
│     Internal Gateway            │ (Gateway API)
│  + EnvoyExtensionPolicy         │
└───────────────┬─────────────────┘
                │ ext-proc
                ▼
┌─────────────────────────────────┐
│    EPP (Endpoint Picker)        │  Analyzes request, selects optimal pod
│    - Prefix cache scoring       │
│    - KV utilization scoring     │
│    - Queue depth scoring        │
└───────────────┬─────────────────┘
                │
                ▼
┌─────────────────────────────────┐
│       InferencePool             │  Pool of vLLM pods
│    (selected by EPP)            │
└─────────────────────────────────┘
```

## Prerequisites

- Kubernetes 1.25+
- Inference Extension CRDs installed (use inference-extension-crds chart)
- Networking layer deployed (provides GatewayClass)
- At least one InferenceService deployed (target for routing)

## Quick Start

```bash
helm install inference-gw ./charts/inference-gateway \
  --namespace llm-platform \
  --set epp.poolName=llama-70b-pool
```

Verify:

```bash
kubectl get gateway -n llm-platform
kubectl get deployment -n llm-platform -l app.kubernetes.io/component=epp
kubectl get pods -n llm-platform -l app.kubernetes.io/component=epp
```

## Values

### Gateway Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `gatewayClassName` | string | `llm-gateway` | GatewayClass to use |
| `gateway.enabled` | bool | `true` | Create internal Gateway |
| `gateway.name` | string | `""` | Gateway name (defaults to chart fullname) |
| `gateway.port` | int | `80` | HTTP listener port |

### EPP Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `epp.image.repository` | string | `registry.k8s.io/gateway-api-inference-extension/epp` | EPP image |
| `epp.image.tag` | string | `v1.3.0` | EPP image tag |
| `epp.replicas` | int | `2` | EPP replica count |
| `epp.poolName` | string | `""` | **Required.** InferencePool name |
| `epp.poolNamespace` | string | `""` | InferencePool namespace (defaults to release namespace) |
| `epp.logLevel` | string | `info` | Log level (debug, info, warn, error) |
| `epp.logEncoder` | string | `json` | Log format (json, console) |

### EPP Resources

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `epp.resources.requests.cpu` | string | `500m` | CPU request |
| `epp.resources.requests.memory` | string | `512Mi` | Memory request |
| `epp.resources.limits.cpu` | string | `2` | CPU limit |
| `epp.resources.limits.memory` | string | `2Gi` | Memory limit |

### Scheduling Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `epp.schedulingConfig.enabled` | bool | `false` | Enable custom scheduling config |
| `epp.schedulingConfig.scorers.prefixCacheScorer` | int | `60` | Weight for prefix cache scoring |
| `epp.schedulingConfig.scorers.kvCacheUtilizationScorer` | int | `30` | Weight for KV-cache utilization |
| `epp.schedulingConfig.scorers.queueScorer` | int | `10` | Weight for queue depth |
| `epp.schedulingConfig.picker` | string | `max-score-picker` | Endpoint picker plugin |
| `epp.schedulingConfig.saturationDetector.queueDepthThreshold` | int | `5` | Queue depth threshold |
| `epp.schedulingConfig.saturationDetector.kvCacheUtilThreshold` | float | `0.8` | KV-cache util threshold |

### EnvoyExtensionPolicy

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `extensionPolicy.enabled` | bool | `true` | Create EnvoyExtensionPolicy |
| `extensionPolicy.targetKind` | string | `Gateway` | Target resource kind |
| `extensionPolicy.responseBodyMode` | string | `Streamed` | Response mode for SSE |
| `extensionPolicy.requestTimeout` | string | `300s` | Inference request timeout |

### Observability

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `serviceMonitor.enabled` | bool | `false` | Create ServiceMonitor |
| `serviceMonitor.interval` | string | `30s` | Scrape interval |
| `dashboards.enabled` | bool | `false` | Create Grafana dashboard |

## Scheduling Configuration

Customize routing behavior by adjusting scorer weights:

```yaml
epp:
  schedulingConfig:
    enabled: true
    scorers:
      # Prioritize KV-cache reuse (reduces TTFT)
      prefixCacheScorer: 70
      # Balance load across pods
      kvCacheUtilizationScorer: 20
      # Avoid pods with long queues
      queueScorer: 10
    saturationDetector:
      # Consider pod saturated when queue > 5
      queueDepthThreshold: 5
      # Consider pod saturated when KV-cache > 80%
      kvCacheUtilThreshold: 0.8
```

### Scorer Behavior

| Scorer | What it optimizes | When to prioritize |
|--------|------------------|-------------------|
| `prefixCacheScorer` | KV-cache reuse | Chat workloads with shared system prompts |
| `kvCacheUtilizationScorer` | Load balancing | Heterogeneous request sizes |
| `queueScorer` | Latency | Latency-sensitive workloads |

## Multiple InferencePools

EPP is one-pool-per-instance. For multiple pools, deploy separate releases:

```bash
# Pool for Llama 70B
helm install inference-gw-llama ./charts/inference-gateway \
  --namespace llm-platform \
  --set epp.poolName=llama-70b-pool

# Pool for Qwen 7B
helm install inference-gw-qwen ./charts/inference-gateway \
  --namespace llm-platform \
  --set epp.poolName=qwen-7b-pool \
  --set gateway.name=qwen-gateway
```

## Integration with LiteLLM

Configure LiteLLM to route through the inference gateway:

```yaml
# litellm-proxy values.yaml
litellm:
  modelList:
    - modelName: llama-70b
      litellmParams:
        model: hosted_vllm/meta-llama/Llama-3.3-70B-Instruct
        # Route through inference gateway instead of direct to model
        apiBase: http://inference-gw-inference-gateway.llm-platform.svc.cluster.local
```

## Troubleshooting

**EPP not routing requests:**

```bash
kubectl logs -n llm-platform -l app.kubernetes.io/component=epp
kubectl get endpointslices -n llm-platform
```

**InferencePool has no ready pods:**

```bash
kubectl get inferencepool -n llm-platform -o yaml
kubectl get pods -l serving.kserve.io/inferenceservice=<name> -n llm-platform
```

**EnvoyExtensionPolicy not applied:**

```bash
kubectl get envoyextensionpolicy -n llm-platform
kubectl describe envoyextensionpolicy -n llm-platform
```

**Gateway not accepting traffic:**

```bash
kubectl get gateway -n llm-platform
kubectl describe gateway -n llm-platform
kubectl get svc -n llm-platform | grep gateway
```

**ext-proc connection failures:**

```bash
# Check EPP service
kubectl get svc -n llm-platform -l app.kubernetes.io/component=epp
kubectl get endpoints -n llm-platform -l app.kubernetes.io/component=epp

# Check Envoy logs
kubectl logs -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=inference-gw
```

**Metrics not appearing:**

```bash
# Check EPP metrics endpoint
kubectl port-forward -n llm-platform svc/inference-gw-epp 9090:9090
curl http://localhost:9090/metrics
```

**Request not using KV-cache:**

```bash
# Check EPP logs for routing decisions
kubectl logs -n llm-platform -l app.kubernetes.io/component=epp --tail=100 | grep -i "prefix\|cache"
```
