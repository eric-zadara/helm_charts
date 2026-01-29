# LiteLLM Proxy

Helm chart for LiteLLM API gateway with multi-tenancy, rate limiting, and caching.

## Overview

LiteLLM Proxy provides:

- **OpenAI-compatible API** - Drop-in replacement for OpenAI SDK
- **Multi-tenancy** - API key authentication, per-tenant rate limiting
- **Caching** - Response caching via Valkey for cost reduction
- **Observability** - Prometheus metrics, structured JSON logging

## Prerequisites

- Kubernetes 1.25+
- PostgreSQL deployed (CNPG cluster with pooler)
- Valkey deployed (bitnami/valkey with Sentinel)
- Networking layer deployed (networking-layer chart)

## Service Discovery

This chart assumes PostgreSQL and Valkey are deployed with these release names:

```bash
# PostgreSQL with CNPG
helm install postgresql cnpg/cluster -n llm-platform \
  --set pooler.enabled=true

# Valkey with Sentinel HA
helm install valkey bitnami/valkey -n llm-platform \
  --set sentinel.enabled=true
```

This creates services:
- `postgresql-pooler-rw` - PostgreSQL connection pooler
- `valkey` - Valkey sentinel service

If you used different release names, override the defaults:

```bash
helm install litellm ./charts/litellm-proxy -n llm-platform \
  --set database.host=mydb-pooler-rw \
  --set database.passwordSecretName=mydb-app \
  --set cache.sentinel.host=mycache \
  --set cache.passwordSecretName=mycache
```

## Traffic Flow

### Direct Routing (Simple)

```
Client -> External Gateway -> LiteLLM -> KServe Predictor -> vLLM
```

Configure with direct predictor URL:
```yaml
litellm:
  modelList:
    - modelName: gpt-4
      litellmParams:
        model: hosted_vllm/meta-llama/Llama-3.3-70B-Instruct
        apiBase: http://llama-70b-predictor.llm-platform.svc.cluster.local
```

### KV-Cache Aware Routing (Recommended)

```
Client -> External Gateway -> LiteLLM -> Internal Gateway -> EPP -> InferencePool -> vLLM
                                              |
                                        EnvoyExtensionPolicy
                                              |
                                    (prefix cache scoring,
                                     KV util scoring,
                                     queue depth scoring)
```

Benefits:
- Routes similar prompts to pods with cached KV states
- Balances load based on KV-cache utilization
- Reduces redundant computation for repeated prefixes

Configure with Internal Gateway URL:
```yaml
litellm:
  modelList:
    - modelName: gpt-4
      litellmParams:
        model: hosted_vllm/meta-llama/Llama-3.3-70B-Instruct
        apiBase: http://inference-gateway.llm-platform.svc.cluster.local
```

Requirements for KV-cache routing:
1. Deploy `inference-gateway` chart with EPP enabled
2. Deploy `model-serving` with `inferencePool.enabled: true`
3. Enable HTTPRoute: `model-serving` with `inferencePoolRoute.enabled: true`

## Quick Start

1. Create required secrets:

```bash
kubectl create secret generic litellm-master-key \
  --from-literal=master-key="sk-$(openssl rand -hex 16)" \
  -n llm-platform

kubectl create secret generic litellm-salt-key \
  --from-literal=salt-key="$(openssl rand -hex 32)" \
  -n llm-platform
```

2. Install the chart (defaults assume postgresql and valkey release names):

```bash
helm install litellm ./charts/litellm-proxy \
  --namespace llm-platform \
  --set masterKey.existingSecret=litellm-master-key \
  --set saltKey.existingSecret=litellm-salt-key
```

3. Verify:

```bash
kubectl get pods -n llm-platform -l app.kubernetes.io/name=litellm-proxy
curl http://litellm-proxy.llm-platform.svc.cluster.local:4000/health
```

## Values

### Image Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `image.repository` | string | `ghcr.io/berriai/litellm-database` | Docker image |
| `image.tag` | string | `v1.80.15-stable.1` | Image tag |
| `replicaCount` | int | `2` | Number of proxy replicas |

### Authentication

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `masterKey.create` | bool | `false` | Create master key secret |
| `masterKey.existingSecret` | string | `""` | Existing secret name |
| `masterKey.existingSecretKey` | string | `master-key` | Key in secret |
| `saltKey.create` | bool | `false` | Create salt key secret |
| `saltKey.existingSecret` | string | `""` | Existing secret name |
| `saltKey.existingSecretKey` | string | `salt-key` | Key in secret |

### Database Connection

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `database.host` | string | `postgresql-pooler-rw` | PostgreSQL host (PgBouncer) |
| `database.port` | int | `5432` | PostgreSQL port |
| `database.name` | string | `app` | Database name |
| `database.user` | string | `app` | Database user |
| `database.passwordSecretName` | string | `postgresql-app` | Secret with DB password |
| `database.passwordSecretKey` | string | `password` | Key in password secret |
| `database.connectionPoolLimit` | int | `10` | Connections per worker |
| `database.connectionTimeout` | int | `60` | Connection timeout (seconds) |

### Cache Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `cache.enabled` | bool | `true` | Enable Valkey caching |
| `cache.sentinel.enabled` | bool | `true` | Use Sentinel for HA |
| `cache.sentinel.host` | string | `valkey` | Sentinel host |
| `cache.sentinel.port` | int | `26379` | Sentinel port |
| `cache.sentinel.serviceName` | string | `mymaster` | Sentinel master name |
| `cache.passwordSecretName` | string | `valkey` | Secret with Valkey password |
| `cache.passwordSecretKey` | string | `valkey-password` | Key in password secret |

### LiteLLM Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `litellm.modelList` | array | `[]` | Model definitions (see below) |
| `litellm.generalSettings.proxy_batch_write_at` | int | `60` | Batch DB writes interval |
| `litellm.generalSettings.request_timeout` | int | `600` | Request timeout (seconds) |
| `litellm.litellmSettings.cache` | bool | `true` | Enable response caching |
| `litellm.litellmSettings.cache_params.ttl` | int | `600` | Cache TTL (seconds) |
| `litellm.litellmSettings.json_logs` | bool | `true` | Enable JSON logging |
| `litellm.litellmSettings.callbacks` | array | `["prometheus"]` | Enabled callbacks |

### HTTPRoute Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `httpRoute.enabled` | bool | `true` | Create HTTPRoute |
| `httpRoute.gateway.name` | string | `""` | Gateway name |
| `httpRoute.gateway.namespace` | string | `""` | Gateway namespace |
| `httpRoute.pathPrefix` | string | `/` | Route path prefix |

### Health Checks

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `healthCheck.separateApp` | bool | `true` | Use separate health endpoint |
| `healthCheck.separatePort` | int | `8001` | Health check port |

### Observability

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `serviceMonitor.enabled` | bool | `false` | Create ServiceMonitor |
| `serviceMonitor.interval` | string | `15s` | Scrape interval |
| `dashboards.enabled` | bool | `false` | Create Grafana dashboard |

## Model Configuration

Configure models in `litellm.modelList`:

```yaml
litellm:
  modelList:
    # Option 1: Direct to KServe predictor (simple, no KV-cache routing)
    - modelName: gpt-4-direct
      litellmParams:
        model: hosted_vllm/meta-llama/Llama-3.3-70B-Instruct
        apiBase: http://llama-70b-predictor.llm-platform.svc.cluster.local
      modelInfo:
        id: gpt-4-direct

    # Option 2: Through Internal Gateway (KV-cache aware - RECOMMENDED)
    - modelName: gpt-4
      litellmParams:
        model: hosted_vllm/meta-llama/Llama-3.3-70B-Instruct
        # Route through Internal Gateway -> EPP -> InferencePool
        apiBase: http://inference-gateway.llm-platform.svc.cluster.local
      modelInfo:
        id: gpt-4

    # Option 3: With rate limits per model
    - modelName: gpt-4-limited
      litellmParams:
        model: hosted_vllm/meta-llama/Llama-3.3-70B-Instruct
        apiBase: http://inference-gateway.llm-platform.svc.cluster.local
        rpm: 100    # Requests per minute
        tpm: 1000000  # Tokens per minute
```

See [Traffic Flow](#traffic-flow) section for architecture details on each routing pattern.

## API Key Management

Create API keys via the admin API:

```bash
# Generate a new API key
curl -X POST http://litellm-proxy:4000/key/generate \
  -H "Authorization: Bearer sk-your-master-key" \
  -H "Content-Type: application/json" \
  -d '{"team_id": "engineering", "max_budget": 100}'

# List existing keys
curl http://litellm-proxy:4000/key/info \
  -H "Authorization: Bearer sk-your-master-key"

# Delete a key
curl -X POST http://litellm-proxy:4000/key/delete \
  -H "Authorization: Bearer sk-your-master-key" \
  -H "Content-Type: application/json" \
  -d '{"keys": ["sk-key-to-delete"]}'
```

## Usage with OpenAI SDK

```python
from openai import OpenAI

client = OpenAI(
    api_key="sk-your-api-key",
    base_url="http://litellm-proxy.llm-platform.svc.cluster.local:4000"
)

response = client.chat.completions.create(
    model="gpt-4",  # Maps to your configured model
    messages=[{"role": "user", "content": "Hello!"}]
)
```

## Caching Configuration

Enable semantic caching for cost reduction:

```yaml
litellm:
  litellmSettings:
    cache: true
    cache_params:
      type: "redis"
      ttl: 600
      namespace: "litellm.caching"
      mode: "default_off"  # Require X-LiteLLM-Cache: true header
```

To enable caching per request:

```bash
curl http://litellm-proxy:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-key" \
  -H "X-LiteLLM-Cache: true" \
  -d '{"model": "gpt-4", "messages": [...]}'
```

## Troubleshooting

**Database connection failed:**

```bash
kubectl exec -it deployment/litellm-proxy -n llm-platform -- env | grep DATABASE
kubectl logs deployment/litellm-proxy -n llm-platform | grep -i "database\|postgres"
```

**Rate limiting not working:**

```bash
kubectl exec -it deployment/litellm-proxy -n llm-platform -- env | grep REDIS
kubectl logs deployment/litellm-proxy -n llm-platform | grep -i "redis\|valkey\|cache"
```

**Model not found:**

```bash
# Check configured models
kubectl get configmap litellm-config -n llm-platform -o yaml

# Verify model endpoint is reachable
kubectl exec -it deployment/litellm-proxy -n llm-platform -- curl http://llama-70b-predictor:80/v1/models
```

**Migration job failed:**

```bash
kubectl get jobs -n llm-platform | grep litellm
kubectl logs job/litellm-migrate -n llm-platform
```

**Health check failures:**

```bash
kubectl describe pod -l app.kubernetes.io/name=litellm-proxy -n llm-platform
kubectl logs -l app.kubernetes.io/name=litellm-proxy -n llm-platform --previous
```

**Salt key warning:**

Never change the salt key after initial deployment with data. Existing encrypted credentials will become unreadable.
