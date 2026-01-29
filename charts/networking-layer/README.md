# Networking Layer

Helm chart for LLM platform networking (Envoy Gateway + Kourier + Knative autoscaler).

## Overview

This chart deploys:

- **Envoy Gateway** - Gateway API implementation with ext-proc support
- **GatewayClass + Gateway** - External ingress for API traffic
- **Kourier** - Knative networking layer for model serving
- **Knative ConfigMaps** - Autoscaler tuned for LLM workloads

## Architecture

```
Internet
    │
    ▼
┌─────────────────────────────┐
│     Envoy Gateway           │ (External Gateway, port 80/443)
│     GatewayClass: llm-gateway│
└─────────────┬───────────────┘
              │
      ┌───────┴───────┐
      │               │
      ▼               ▼
┌──────────┐   ┌─────────────────────┐
│ LiteLLM  │   │  Inference Gateway  │ (Internal Gateway)
│  Proxy   │   │   (EPP ext-proc)    │
└──────────┘   └──────────┬──────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │       Kourier         │ (Knative networking)
              │     (ClusterIP)       │
              └───────────┬───────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │        KServe         │ (InferenceService)
              │     vLLM / Ollama     │
              └───────────────────────┘
```

## Prerequisites

- Kubernetes 1.25+
- Gateway API CRDs installed (use gateway-api chart)
- Knative Serving CRDs installed (use knative-serving-crds chart)
- cert-manager (optional, for TLS)

## Quick Start

```bash
helm install networking ./charts/networking-layer \
  --namespace llm-platform --create-namespace
```

Verify:

```bash
kubectl get gateway -n llm-platform
kubectl get pods -n kourier-system
kubectl get configmap -n knative-serving
```

## Values

### Envoy Gateway Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `envoyGateway.enabled` | bool | `true` | Deploy Envoy Gateway |
| `envoyGateway.preserveRequestId` | bool | `true` | Preserve X-Request-ID headers for correlation |

### GatewayClass and Gateway

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `gatewayClass.name` | string | `llm-gateway` | GatewayClass name |
| `gateway.name` | string | `""` | Gateway name (defaults to release name) |
| `gateway.hostname` | string | `""` | Hostname for TLS/routing |
| `gateway.redirectHttps` | bool | `false` | Redirect HTTP to HTTPS |

### Kourier Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `kourier.enabled` | bool | `true` | Deploy Kourier |
| `kourier.service.type` | string | `ClusterIP` | Kourier service type (ClusterIP for internal-only) |
| `kourier.controller.replicas` | int | `1` | Kourier controller replicas |
| `kourier.gateway.replicas` | int | `1` | Kourier gateway (Envoy) replicas |

### TLS Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `tls.enabled` | bool | `false` | Enable TLS termination |
| `tls.secretName` | string | `""` | TLS secret name |
| `tls.certManager.enabled` | bool | `false` | Use cert-manager for certificates |
| `tls.certManager.clusterIssuer` | string | `letsencrypt-prod` | ClusterIssuer name |

### Load Balancer Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `loadBalancer.provider` | string | `aws` | Cloud provider (aws, gcp, azure, bare-metal) |
| `loadBalancer.aws.scheme` | string | `internet-facing` | AWS LB scheme |
| `loadBalancer.aws.nlbTargetType` | string | `ip` | NLB target type |

### Knative Autoscaler Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `knative.enabled` | bool | `true` | Deploy Knative ConfigMaps |
| `knative.autoscaler.enableScaleToZero` | bool | `true` | Enable scale-to-zero globally |
| `knative.autoscaler.scaleToZeroGracePeriod` | string | `30s` | Grace period for scale-to-zero |
| `knative.autoscaler.scaleToZeroPodRetentionPeriod` | string | `60s` | Min time last pod stays after scale-to-zero |
| `knative.autoscaler.stableWindow` | string | `60s` | Time window for averaging concurrency |
| `knative.autoscaler.scaleDownDelay` | string | `300s` | Delay before scale-down (5 min for LLM) |
| `knative.autoscaler.maxScaleUpRate` | string | `2.0` | Max pods per minute scale-up rate |
| `knative.autoscaler.containerConcurrencyTargetDefault` | string | `10` | Default concurrency target |

## TLS Configuration

Enable TLS with cert-manager:

```yaml
tls:
  enabled: true
  certManager:
    enabled: true
    clusterIssuer: letsencrypt-prod
gateway:
  hostname: llm.example.com
```

Or use existing certificate:

```yaml
tls:
  enabled: true
  existingSecret: my-tls-secret
gateway:
  hostname: llm.example.com
```

## Autoscaling Tuning

For LLM workloads with expensive cold starts:

```yaml
knative:
  autoscaler:
    # Longer delay before scaling down (GPU cold start is expensive)
    scaleDownDelay: "600s"
    # Conservative scale-up to avoid over-provisioning GPUs
    maxScaleUpRate: "1.0"
    # Lower concurrency target for large models
    containerConcurrencyTargetDefault: "5"
```

## Troubleshooting

**Gateway not getting external IP:**

```bash
kubectl get svc -n envoy-gateway-system
kubectl describe gateway -n llm-platform
```

**Envoy Gateway pods not running:**

```bash
kubectl get pods -n envoy-gateway-system
kubectl logs -n envoy-gateway-system -l control-plane=envoy-gateway
```

**Kourier not routing:**

```bash
kubectl get ksvc -A
kubectl logs -n kourier-system -l app=3scale-kourier-gateway
```

**HTTPRoute not attached to Gateway:**

```bash
kubectl get httproute -n llm-platform
kubectl describe httproute -n llm-platform
```

**Knative autoscaler issues:**

```bash
kubectl get configmap config-autoscaler -n knative-serving -o yaml
kubectl logs -n knative-serving -l app=autoscaler
```

**Request ID not propagating:**

```bash
# Check EnvoyProxy configuration
kubectl get envoyproxy -n envoy-gateway-system -o yaml
```
