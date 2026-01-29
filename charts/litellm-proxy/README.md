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

## Values

### Pod Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity rules for pod scheduling |
| extraEnv | object | `{}` | Extra environment variables as key-value pairs |
| extraEnvFrom | list | `[]` | Extra environment variable sources (secretRef, configMapRef) |
| nodeSelector | object | `{}` | Node selector constraints |
| podAnnotations | object | `{}` | Additional pod annotations |
| podLabels | object | `{}` | Additional pod labels |
| tolerations | list | `[]` | Tolerations for pod scheduling |

### Resources and Scaling

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| autoscaling | object | `{"enabled":false,"maxReplicas":10,"minReplicas":2,"targetCPUUtilizationPercentage":80,"targetMemoryUtilizationPercentage":""}` | HPA configuration |
| podDisruptionBudget | object | `{"enabled":false,"minAvailable":1}` | PodDisruptionBudget configuration |
| resources | object | `{"limits":{"cpu":"2000m","memory":"2Gi"},"requests":{"cpu":"500m","memory":"512Mi"}}` | Resource requirements |
| terminationGracePeriodSeconds | int | `90` | Termination grace period (allows in-flight requests to complete) |

### Cache Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| cache | object | `{"enabled":true,"host":"","passwordSecretKey":"valkey-password","passwordSecretName":"valkey","port":6379,"sentinel":{"enabled":true,"host":"valkey","port":26379,"serviceName":"mymaster"}}` | Cache and rate limiting connection (Valkey). Deploy Valkey: helm install valkey bitnami/valkey --set sentinel.enabled=true |

### Observability

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| dashboards | object | `{"enabled":false,"folderAnnotation":"LLM Platform"}` | Grafana dashboard configuration |
| serviceMonitor | object | `{"enabled":false,"interval":"15s","scrapeTimeout":"10s"}` | Prometheus ServiceMonitor |

### Database Connection

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| database | object | `{"connectionPoolLimit":10,"connectionTimeout":60,"host":"postgresql-pooler-rw","name":"app","passwordSecretKey":"password","passwordSecretName":"postgresql-app","port":5432,"user":"app"}` | Database connection (PostgreSQL via CNPG). Deploy CNPG cluster: helm install postgresql cnpg/cluster Service name follows: <release>-pooler-rw |

### Image Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| fullnameOverride | string | `""` | Override full release name |
| image | object | `{"pullPolicy":"IfNotPresent","repository":"ghcr.io/berriai/litellm-database","tag":"v1.80.15-stable.1"}` | Docker image configuration |
| imagePullSecrets | list | `[]` | Image pull secrets for private registries |
| nameOverride | string | `""` | Override chart name |
| replicaCount | int | `2` | Number of LiteLLM proxy replicas |

### Health Checks

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| healthCheck | object | `{"liveness":{"failureThreshold":3,"periodSeconds":15,"timeoutSeconds":5},"readiness":{"failureThreshold":3,"periodSeconds":10,"timeoutSeconds":5},"separateApp":true,"separatePort":8001,"startup":{"failureThreshold":30,"initialDelaySeconds":30,"periodSeconds":10,"timeoutSeconds":5}}` | Health check configuration |

### HTTPRoute Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| httpRoute | object | `{"enabled":true,"gateway":{"name":"","namespace":""},"hostname":"","pathPrefix":"/"}` | HTTPRoute configuration (Envoy Gateway integration) |

### LiteLLM Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| litellm | object | `{"generalSettings":{"allow_requests_on_db_unavailable":true,"disable_error_logs":true,"proxy_batch_write_at":60,"request_timeout":600},"litellmSettings":{"cache":true,"cache_params":{"mode":"default_off","namespace":"litellm.caching","ttl":600,"type":"redis"},"callbacks":["prometheus"],"fallbacks":[],"json_logs":true,"num_retries":2,"set_verbose":false,"turn_off_message_logging":false},"modelList":[],"routerSettings":{"enable_pre_call_checks":true,"model_group_alias":{},"routing_strategy":"simple-shuffle"}}` | LiteLLM proxy configuration (generates litellm_config.yaml) |

### Logging

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| logging | object | `{"disableSpendLogs":false,"retentionInterval":"1d","retentionPeriod":"30d","storePrompts":false}` | Request logging configuration |

### Authentication

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| masterKey | object | `{"create":false,"existingSecret":"","existingSecretKey":"master-key","value":""}` | Master key configuration for admin API authentication |
| saltKey | object | `{"create":false,"existingSecret":"","existingSecretKey":"salt-key","value":""}` | Salt key for encrypting API credentials stored in PostgreSQL. WARNING: Never change after initial deployment with data -- existing encrypted data becomes unreadable if the salt key changes. |

### Migration Job

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| migrationJob | object | `{"backoffLimit":4,"enabled":true,"ttlSecondsAfterFinished":120}` | Migration job configuration (Prisma schema migration as Helm pre-install/pre-upgrade hook) |

### Service Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| service | object | `{"port":4000,"type":"ClusterIP"}` | Service configuration |

### Other Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| autoscaling.enabled | bool | `false` | Enable HPA |
| autoscaling.maxReplicas | int | `10` | Maximum replicas |
| autoscaling.minReplicas | int | `2` | Minimum replicas |
| autoscaling.targetCPUUtilizationPercentage | int | `80` | Target CPU utilization percentage |
| autoscaling.targetMemoryUtilizationPercentage | string | `""` | Target memory utilization percentage (optional, empty to disable) |
| cache.enabled | bool | `true` | Enable Valkey integration for caching and distributed rate limiting |
| cache.host | string | `""` | Direct connection host (used when sentinel.enabled=false) |
| cache.passwordSecretKey | string | `"valkey-password"` | Key within password secret |
| cache.passwordSecretName | string | `"valkey"` | Secret containing Valkey password. Secret name follows: <release> (bitnami convention) |
| cache.port | int | `6379` | Direct connection port (used when sentinel.enabled=false) |
| cache.sentinel | object | `{"enabled":true,"host":"valkey","port":26379,"serviceName":"mymaster"}` | Sentinel HA configuration |
| cache.sentinel.enabled | bool | `true` | Enable Sentinel discovery for automatic failover |
| cache.sentinel.host | string | `"valkey"` | Sentinel host (Valkey service). Service name follows: <release> |
| cache.sentinel.port | int | `26379` | Sentinel port |
| cache.sentinel.serviceName | string | `"mymaster"` | Sentinel service name (master group name) |
| dashboards.enabled | bool | `false` | Enable dashboard ConfigMap creation (requires Grafana sidecar) |
| dashboards.folderAnnotation | string | `"LLM Platform"` | Grafana folder annotation for dashboard organization |
| database.connectionPoolLimit | int | `10` | Connection pool limit per worker process. Formula: PgBouncer_max_client_conn / (num_workers x num_pods) |
| database.connectionTimeout | int | `60` | Connection timeout in seconds |
| database.host | string | `"postgresql-pooler-rw"` | PostgreSQL host (PgBouncer service) |
| database.name | string | `"app"` | Database name |
| database.passwordSecretKey | string | `"password"` | Key within password secret |
| database.passwordSecretName | string | `"postgresql-app"` | Secret containing PostgreSQL password. Secret name follows: <release>-app (CNPG convention) |
| database.port | int | `5432` | PostgreSQL port |
| database.user | string | `"app"` | Database user |
| healthCheck.liveness | object | `{"failureThreshold":3,"periodSeconds":15,"timeoutSeconds":5}` | Liveness probe |
| healthCheck.readiness | object | `{"failureThreshold":3,"periodSeconds":10,"timeoutSeconds":5}` | Readiness probe |
| healthCheck.separateApp | bool | `true` | Use separate health check app/port (recommended for production). Prevents health check timeouts under heavy load. |
| healthCheck.separatePort | int | `8001` | Separate health check port |
| healthCheck.startup | object | `{"failureThreshold":30,"initialDelaySeconds":30,"periodSeconds":10,"timeoutSeconds":5}` | Startup probe (allows time for LiteLLM initialization) |
| httpRoute.enabled | bool | `true` | Enable HTTPRoute creation |
| httpRoute.gateway | object | `{"name":"","namespace":""}` | Gateway reference |
| httpRoute.gateway.name | string | `""` | Gateway name (defaults to networking-layer gateway) |
| httpRoute.gateway.namespace | string | `""` | Gateway namespace (defaults to release namespace) |
| httpRoute.hostname | string | `""` | Route hostname (optional, for host-based routing) |
| httpRoute.pathPrefix | string | `"/"` | Route path prefix |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy |
| image.repository | string | `"ghcr.io/berriai/litellm-database"` | Docker image repository (database variant includes Prisma support) |
| image.tag | string | `"v1.80.15-stable.1"` | Image tag (pin to specific stable version for reproducibility) |
| litellm.generalSettings | object | `{"allow_requests_on_db_unavailable":true,"disable_error_logs":true,"proxy_batch_write_at":60,"request_timeout":600}` | General settings (merged into config.yaml general_settings) |
| litellm.generalSettings.allow_requests_on_db_unavailable | bool | `true` | Allow requests if DB is temporarily unavailable |
| litellm.generalSettings.disable_error_logs | bool | `true` | Disable verbose error logs in DB (recommended for production) |
| litellm.generalSettings.proxy_batch_write_at | int | `60` | Batch spend writes every N seconds (reduces DB load) |
| litellm.generalSettings.request_timeout | int | `600` | Request timeout in seconds |
| litellm.litellmSettings | object | `{"cache":true,"cache_params":{"mode":"default_off","namespace":"litellm.caching","ttl":600,"type":"redis"},"callbacks":["prometheus"],"fallbacks":[],"json_logs":true,"num_retries":2,"set_verbose":false,"turn_off_message_logging":false}` | LiteLLM settings (merged into config.yaml litellm_settings) |
| litellm.litellmSettings.cache | bool | `true` | Enable response caching |
| litellm.litellmSettings.cache_params | object | `{"mode":"default_off","namespace":"litellm.caching","ttl":600,"type":"redis"}` | Cache parameters (infrastructure wiring added automatically from cache.* values) |
| litellm.litellmSettings.cache_params.mode | string | `"default_off"` | Cache mode: "default_off" requires per-request opt-in, "default_on" caches all |
| litellm.litellmSettings.cache_params.namespace | string | `"litellm.caching"` | Cache key namespace |
| litellm.litellmSettings.cache_params.ttl | int | `600` | Cache TTL in seconds |
| litellm.litellmSettings.callbacks | list | `["prometheus"]` | Prometheus callbacks for metrics export |
| litellm.litellmSettings.fallbacks | list | `[]` | Fallback chains (model group name -> fallback model groups) |
| litellm.litellmSettings.json_logs | bool | `true` | Enable JSON structured logging |
| litellm.litellmSettings.num_retries | int | `2` | Number of retries on failure |
| litellm.litellmSettings.set_verbose | bool | `false` | Disable verbose output (recommended for production) |
| litellm.litellmSettings.turn_off_message_logging | bool | `false` | Turn off message content logging (privacy) |
| litellm.modelList | list | `[]` | Model list (array of model definitions routed to KServe endpoints). Each entry creates a model accessible via /v1/chat/completions. See README for routing pattern examples. |
| litellm.routerSettings | object | `{"enable_pre_call_checks":true,"model_group_alias":{},"routing_strategy":"simple-shuffle"}` | Router settings (merged into config.yaml router_settings) |
| litellm.routerSettings.enable_pre_call_checks | bool | `true` | Enable pre-call checks (context window, model availability) |
| litellm.routerSettings.model_group_alias | object | `{}` | Model group aliases (supports hidden models) |
| litellm.routerSettings.routing_strategy | string | `"simple-shuffle"` | Routing strategy |
| logging.disableSpendLogs | bool | `false` | Disable spend logs entirely (saves DB space, lose UI usage view) |
| logging.retentionInterval | string | `"1d"` | Retention cleanup interval |
| logging.retentionPeriod | string | `"30d"` | Spend log retention period (e.g., "30d", "90d") |
| logging.storePrompts | bool | `false` | Store prompts/responses in spend_logs (false for privacy) |
| masterKey.create | bool | `false` | Create a Kubernetes Secret from the value below (set false to use existing) |
| masterKey.existingSecret | string | `""` | Name of an existing secret containing the master key |
| masterKey.existingSecretKey | string | `"master-key"` | Key within the existing secret |
| masterKey.value | string | `""` | Master key value (only used if create=true; should start with "sk-") |
| migrationJob.backoffLimit | int | `4` | Job retry limit |
| migrationJob.enabled | bool | `true` | Enable Prisma migration job |
| migrationJob.ttlSecondsAfterFinished | int | `120` | TTL after completion (seconds) |
| podDisruptionBudget.enabled | bool | `false` | Enable PDB |
| podDisruptionBudget.minAvailable | int | `1` | Minimum available pods during disruptions |
| saltKey.create | bool | `false` | Create a Kubernetes Secret from the value below (set false to use existing) |
| saltKey.existingSecret | string | `""` | Name of an existing secret containing the salt key |
| saltKey.existingSecretKey | string | `"salt-key"` | Key within the existing secret |
| saltKey.value | string | `""` | Salt key value (only used if create=true) |
| service.port | int | `4000` | Service port (LiteLLM default) |
| service.type | string | `"ClusterIP"` | Service type |
| serviceMonitor.enabled | bool | `false` | Enable ServiceMonitor creation |
| serviceMonitor.interval | string | `"15s"` | Scrape interval |
| serviceMonitor.scrapeTimeout | string | `"10s"` | Scrape timeout |

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
