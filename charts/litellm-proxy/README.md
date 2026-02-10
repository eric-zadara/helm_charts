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
| cache | object | `{"enabled":true,"external":{"host":"","passwordSecretKey":"password","port":6379,"secretName":"","sentinel":{"enabled":false,"port":26379,"serviceName":"mymaster"}},"internal":{"enabled":true,"image":"docker.io/valkey/valkey:8-alpine","password":"","persistence":{"enabled":false,"size":"1Gi","storageClass":""},"replicas":1,"resources":{"limits":{"cpu":"500m","memory":"512Mi"},"requests":{"cpu":"100m","memory":"256Mi"}}}}` | Cache configuration (Redis/Valkey) |

### Observability

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| dashboards | object | `{"enabled":false,"folderAnnotation":"LLM Platform"}` | Grafana dashboard configuration |
| serviceMonitor | object | `{"enabled":false,"interval":"15s","scrapeTimeout":"10s"}` | Prometheus ServiceMonitor |

### Database Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| database | object | `{"connectionPoolLimit":10,"connectionTimeout":60,"external":{"host":"","name":"litellm","passwordSecretKey":"password","port":5432,"secretName":"","user":"litellm"},"internal":{"database":"litellm","enabled":true,"imageName":"ghcr.io/cloudnative-pg/postgresql:17.4","instances":1,"owner":"litellm","parameters":{"max_connections":"200","shared_buffers":"256MB"},"pooler":{"defaultPoolSize":50,"enabled":true,"instances":2,"maxClientConn":1000,"poolMode":"transaction"},"resources":{"limits":{"cpu":"1000m","memory":"1Gi"},"requests":{"cpu":"250m","memory":"512Mi"}},"storageClass":"","storageSize":"10Gi"}}` | Database configuration (PostgreSQL) |

### Image Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| fullnameOverride | string | `""` | Override full release name |
| image | object | `{"pullPolicy":"IfNotPresent","repository":"ghcr.io/berriai/litellm-database","tag":"main-v1.81.3-stable"}` | Docker image configuration |
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

### Init Containers

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| initContainers | object | `{"waitForCache":true,"waitForDatabase":true}` | Init container configuration for waiting on dependencies |

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
| masterKey | object | `{"create":true,"existingSecret":"","existingSecretKey":"master-key","value":""}` | Master key configuration for admin API authentication |
| saltKey | object | `{"create":true,"existingSecret":"","existingSecretKey":"salt-key","value":""}` | Salt key for encrypting API credentials stored in PostgreSQL. WARNING: Never change after initial deployment with data -- existing encrypted data becomes unreadable if the salt key changes. |

### Migration Job

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| migrationJob | object | `{"backoffLimit":4,"enabled":true,"resources":{"limits":{"cpu":"500m","memory":"1Gi"},"requests":{"cpu":"100m","memory":"512Mi"}},"ttlSecondsAfterFinished":120}` | Migration job configuration (Prisma schema migration as Helm post-install/post-upgrade hook) |

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
| cache.enabled | bool | `true` | Enable caching and distributed rate limiting |
| cache.external | object | `{"host":"","passwordSecretKey":"password","port":6379,"secretName":"","sentinel":{"enabled":false,"port":26379,"serviceName":"mymaster"}}` | External cache connection (used when internal.enabled=false) |
| cache.external.host | string | `""` | Redis/Valkey host |
| cache.external.passwordSecretKey | string | `"password"` | Key within the password secret |
| cache.external.port | int | `6379` | Redis/Valkey port |
| cache.external.secretName | string | `""` | Secret containing the password (required when internal.enabled=false) |
| cache.external.sentinel | object | `{"enabled":false,"port":26379,"serviceName":"mymaster"}` | Enable Sentinel mode for HA |
| cache.external.sentinel.port | int | `26379` | Sentinel port |
| cache.external.sentinel.serviceName | string | `"mymaster"` | Sentinel master name |
| cache.internal | object | `{"enabled":true,"image":"docker.io/valkey/valkey:8-alpine","password":"","persistence":{"enabled":false,"size":"1Gi","storageClass":""},"replicas":1,"resources":{"limits":{"cpu":"500m","memory":"512Mi"},"requests":{"cpu":"100m","memory":"256Mi"}}}` | Internal Valkey deployment (enabled by default) Creates a Valkey instance for caching and rate limiting |
| cache.internal.enabled | bool | `true` | Enable internal Valkey deployment |
| cache.internal.image | string | `"docker.io/valkey/valkey:8-alpine"` | Valkey image |
| cache.internal.password | string | `""` | Password for Valkey (auto-generated if empty) |
| cache.internal.persistence | object | `{"enabled":false,"size":"1Gi","storageClass":""}` | Storage persistence |
| cache.internal.replicas | int | `1` | Number of Valkey replicas |
| cache.internal.resources | object | `{"limits":{"cpu":"500m","memory":"512Mi"},"requests":{"cpu":"100m","memory":"256Mi"}}` | Resource requests/limits |
| dashboards.enabled | bool | `false` | Enable dashboard ConfigMap creation (requires Grafana sidecar) |
| dashboards.folderAnnotation | string | `"LLM Platform"` | Grafana folder annotation for dashboard organization |
| database.connectionPoolLimit | int | `10` | Connection pool limit per worker process Formula: PgBouncer_max_client_conn / (num_workers x num_pods) |
| database.connectionTimeout | int | `60` | Connection timeout in seconds |
| database.external | object | `{"host":"","name":"litellm","passwordSecretKey":"password","port":5432,"secretName":"","user":"litellm"}` | External database connection (used when internal.enabled=false) |
| database.external.host | string | `""` | PostgreSQL host |
| database.external.name | string | `"litellm"` | Database name |
| database.external.passwordSecretKey | string | `"password"` | Key within the password secret |
| database.external.port | int | `5432` | PostgreSQL port |
| database.external.secretName | string | `""` | Secret containing the password (required when internal.enabled=false) Secret must have key specified in passwordSecretKey |
| database.external.user | string | `"litellm"` | Database user |
| database.internal | object | `{"database":"litellm","enabled":true,"imageName":"ghcr.io/cloudnative-pg/postgresql:17.4","instances":1,"owner":"litellm","parameters":{"max_connections":"200","shared_buffers":"256MB"},"pooler":{"defaultPoolSize":50,"enabled":true,"instances":2,"maxClientConn":1000,"poolMode":"transaction"},"resources":{"limits":{"cpu":"1000m","memory":"1Gi"},"requests":{"cpu":"250m","memory":"512Mi"}},"storageClass":"","storageSize":"10Gi"}` | Internal CNPG PostgreSQL cluster (enabled by default) Creates a highly-available PostgreSQL cluster with PgBouncer pooling |
| database.internal.database | string | `"litellm"` | Database name to create |
| database.internal.enabled | bool | `true` | Enable internal CNPG cluster deployment |
| database.internal.imageName | string | `"ghcr.io/cloudnative-pg/postgresql:17.4"` | PostgreSQL image |
| database.internal.instances | int | `1` | Number of PostgreSQL instances (1 for dev, 3 for HA) |
| database.internal.owner | string | `"litellm"` | Owner username |
| database.internal.parameters | object | `{"max_connections":"200","shared_buffers":"256MB"}` | PostgreSQL parameters |
| database.internal.pooler | object | `{"defaultPoolSize":50,"enabled":true,"instances":2,"maxClientConn":1000,"poolMode":"transaction"}` | PgBouncer pooler configuration |
| database.internal.pooler.defaultPoolSize | int | `50` | Default connections per pool |
| database.internal.pooler.enabled | bool | `true` | Enable PgBouncer connection pooling |
| database.internal.pooler.instances | int | `2` | Number of pooler instances |
| database.internal.pooler.maxClientConn | int | `1000` | Maximum client connections |
| database.internal.pooler.poolMode | string | `"transaction"` | Pool mode (transaction recommended) |
| database.internal.resources | object | `{"limits":{"cpu":"1000m","memory":"1Gi"},"requests":{"cpu":"250m","memory":"512Mi"}}` | Resource requests/limits |
| database.internal.storageClass | string | `""` | Storage class (leave empty for default) |
| database.internal.storageSize | string | `"10Gi"` | Storage size for PostgreSQL data |
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
| image.repository | string | `"ghcr.io/berriai/litellm-database"` | Docker image repository (database variant includes Prisma support) Use docker.litellm.ai registry as recommended by LiteLLM docs |
| image.tag | string | `"main-v1.81.3-stable"` | Image tag (use main-stable or pin to specific version like main-v1.81.0) See: https://docs.litellm.ai/docs/proxy/deploy |
| initContainers.waitForCache | bool | `true` | Wait for cache to be reachable before starting (recommended for production) |
| initContainers.waitForDatabase | bool | `true` | Wait for database to be reachable before starting (recommended for production) |
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
| litellm.modelList | list | `[]` | Model list (array of model definitions routed to KServe endpoints). Each entry creates a model accessible via /v1/chat/completions. See README for routing pattern examples.  Example: Route through Internal Gateway for KV-cache aware routing modelList:   - modelName: gpt-4     litellmParams:       model: hosted_vllm/meta-llama/Llama-3.3-70B-Instruct       # Use Internal Gateway for KV-cache aware routing (recommended):       apiBase: http://inference-gateway.llm-platform.svc.cluster.local       # Or use direct predictor URL (simpler, no KV-cache routing):       # apiBase: http://llama-70b-predictor.llm-platform.svc.cluster.local |
| litellm.routerSettings | object | `{"enable_pre_call_checks":true,"model_group_alias":{},"routing_strategy":"simple-shuffle"}` | Router settings (merged into config.yaml router_settings) |
| litellm.routerSettings.enable_pre_call_checks | bool | `true` | Enable pre-call checks (context window, model availability) |
| litellm.routerSettings.model_group_alias | object | `{}` | Model group aliases (supports hidden models) |
| litellm.routerSettings.routing_strategy | string | `"simple-shuffle"` | Routing strategy |
| logging.disableSpendLogs | bool | `false` | Disable spend logs entirely (saves DB space, lose UI usage view) |
| logging.retentionInterval | string | `"1d"` | Retention cleanup interval |
| logging.retentionPeriod | string | `"30d"` | Spend log retention period (e.g., "30d", "90d") |
| logging.storePrompts | bool | `false` | Store prompts/responses in spend_logs (false for privacy) |
| masterKey.create | bool | `true` | Create a Kubernetes Secret from the value below (set false to use existing) |
| masterKey.existingSecret | string | `""` | Name of an existing secret containing the master key |
| masterKey.existingSecretKey | string | `"master-key"` | Key within the existing secret |
| masterKey.value | string | `""` | Master key value (auto-generated if empty and create=true) |
| migrationJob.backoffLimit | int | `4` | Job retry limit |
| migrationJob.enabled | bool | `true` | Enable Prisma migration job |
| migrationJob.resources | object | `{"limits":{"cpu":"500m","memory":"1Gi"},"requests":{"cpu":"100m","memory":"512Mi"}}` | Resource requirements for migration job (Prisma can be memory-hungry) |
| migrationJob.ttlSecondsAfterFinished | int | `120` | TTL after completion (seconds) |
| podDisruptionBudget.enabled | bool | `false` | Enable PDB |
| podDisruptionBudget.minAvailable | int | `1` | Minimum available pods during disruptions |
| postgresql.cluster.imageName | string | `"ghcr.io/cloudnative-pg/postgresql:17.4"` |  |
| postgresql.cluster.initdb.database | string | `"litellm"` |  |
| postgresql.cluster.initdb.owner | string | `"litellm"` |  |
| postgresql.cluster.instances | int | `1` |  |
| postgresql.cluster.postgresql.parameters.max_connections | string | `"200"` |  |
| postgresql.cluster.postgresql.parameters.shared_buffers | string | `"256MB"` |  |
| postgresql.cluster.resources.limits.cpu | string | `"1000m"` |  |
| postgresql.cluster.resources.limits.memory | string | `"1Gi"` |  |
| postgresql.cluster.resources.requests.cpu | string | `"250m"` |  |
| postgresql.cluster.resources.requests.memory | string | `"512Mi"` |  |
| postgresql.cluster.storage.size | string | `"10Gi"` |  |
| postgresql.mode | string | `"standalone"` |  |
| postgresql.poolers[0].instances | int | `2` |  |
| postgresql.poolers[0].name | string | `"rw"` |  |
| postgresql.poolers[0].parameters.default_pool_size | string | `"50"` |  |
| postgresql.poolers[0].parameters.max_client_conn | string | `"1000"` |  |
| postgresql.poolers[0].poolMode | string | `"transaction"` |  |
| postgresql.poolers[0].type | string | `"rw"` |  |
| postgresql.type | string | `"postgresql"` |  |
| saltKey.create | bool | `true` | Create a Kubernetes Secret from the value below (set false to use existing) |
| saltKey.existingSecret | string | `""` | Name of an existing secret containing the salt key |
| saltKey.existingSecretKey | string | `"salt-key"` | Key within the existing secret |
| saltKey.value | string | `""` | Salt key value (auto-generated if empty and create=true) |
| service.port | int | `4000` | Service port (LiteLLM default) |
| service.type | string | `"ClusterIP"` | Service type |
| serviceMonitor.enabled | bool | `false` | Enable ServiceMonitor creation |
| serviceMonitor.interval | string | `"15s"` | Scrape interval |
| serviceMonitor.scrapeTimeout | string | `"10s"` | Scrape timeout |
| valkey.architecture | string | `"standalone"` |  |
| valkey.auth.enabled | bool | `true` |  |
| valkey.auth.password | string | `""` |  |
| valkey.master.persistence.enabled | bool | `false` |  |
| valkey.master.resources.limits.cpu | string | `"500m"` |  |
| valkey.master.resources.limits.memory | string | `"512Mi"` |  |
| valkey.master.resources.requests.cpu | string | `"100m"` |  |
| valkey.master.resources.requests.memory | string | `"256Mi"` |  |

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
