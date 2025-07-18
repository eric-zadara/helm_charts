# lightrag-server

![Version: 0.0.8](https://img.shields.io/badge/Version-0.0.8-informational?style=flat-square) ![AppVersion: 1.3.8](https://img.shields.io/badge/AppVersion-1.3.8-informational?style=flat-square)

## Requirements

| Repository | Name | Version |
|------------|------|---------|
| https://charts.bitnami.com/bitnami | neo4j | 0.4.8 |
| https://charts.bitnami.com/bitnami | redis | 20.1.7 |
| https://cloudnative-pg.github.io/charts | cnpg(cluster) | 0.0.11 |

## Values

### Deployment

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| deployment.replicaCount | int | `1` | Set number of replicas |

### Resources

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| deployment.resources.limits | object | `{"cpu":"1000m","memory":"2Gi"}` | Resource limits for web pods |
| deployment.resources.requests | object | `{"cpu":"500m","memory":"1Gi"}` | Resource requests for web pods |

### Ingress configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| ingress.annotations | object | `{}` | Optional addition annotations for the ingress configuration |
| ingress.enabled | bool | `false` | Enable ingress |
| ingress.hostname | string | `""` | Set ingress domain name. Optional(If not specified, creates catch all with https disabled) |
| ingress.ingressClassName | string | `"traefik"` | Set name of ingress controller |
| ingress.tls | bool | `false` | Enable TLS |

### Other Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| cnpg.backups.enabled | bool | `false` |  |
| cnpg.cluster.affinity.topologyKey | string | `"kubernetes.io/hostname"` |  |
| cnpg.cluster.enableSuperuserAccess | bool | `true` |  |
| cnpg.cluster.imageName | string | `"ghcr.io/eric-zadara/pgvector:17.4-0.8.0"` |  |
| cnpg.cluster.instances | int | `3` | Number of psql replicas. 1 is master, N-1 are replica |
| cnpg.cluster.monitoring.additionalLabels.release | string | `"victoria-metrics-k8s-stack"` |  |
| cnpg.cluster.monitoring.enabled | bool | `false` |  |
| cnpg.cluster.postgresGID | int | `999` |  |
| cnpg.cluster.postgresUID | int | `999` |  |
| cnpg.cluster.postgresql.max_connections | string | `"500"` | Max psql connections. Default was 100 |
| cnpg.cluster.postgresql.max_locks_per_transaction | string | `"128"` | Max locks per transaction. Default was 64 |
| cnpg.enabled | bool | `true` | Enable preconfigured cloudnative-pg psql configuration |
| cnpg.mode | string | `"standalone"` |  |
| cnpg.pooler.enabled | bool | `true` |  |
| cnpg.pooler.instances | int | `2` | Number of psql poolers |
| cnpg.pooler.monitoring.additionalLabels.release | string | `"victoria-metrics-k8s-stack"` |  |
| cnpg.pooler.monitoring.enabled | bool | `false` |  |
| cnpg.pooler.parameters.default_pool_size | string | `"50"` | Pool size. Default was 25 |
| cnpg.pooler.parameters.max_client_conn | string | `"1000"` | Max client connections, default was 1000 |
| cnpg.pooler.parameters.reserve_pool_size | string | `"25"` | Reservice pool size, default was 0/disabled |
| cnpg.type | string | `"postgresql"` |  |
| deployment.updateStrategy.type | string | `"RollingUpdate"` |  |
| image.repository | string | `"ghcr.io/hkuds/lightrag"` |  |
| lightrag.embedding_binding | string | `"ollama"` |  |
| lightrag.embedding_binding_api_key | string | `""` |  |
| lightrag.embedding_binding_host | string | `"http://ollama.ollama.svc.cluster.local:11434"` |  |
| lightrag.embedding_dim | int | `1024` |  |
| lightrag.embedding_model | string | `"bge-m3:latest"` |  |
| lightrag.llm_binding | string | `"ollama"` |  |
| lightrag.llm_binding_api_key | string | `""` |  |
| lightrag.llm_binding_host | string | `"http://ollama.ollama.svc.cluster.local:11434"` |  |
| lightrag.llm_model | string | `"qwen3:32b"` |  |
| lightrag.max_tokens | int | `16384` |  |
| lightrag.summary_language | string | `"English"` |  |
| lightrag.timeout | int | `600` |  |
| nameOverride | string | `""` |  |
| neo4j.auth.password | string | `"everyone-check-fish-kind-language"` |  |
| neo4j.enabled | bool | `true` |  |
| neo4j.service.type | string | `"ClusterIP"` |  |
| neo4j.usePasswordFiles | bool | `false` |  |
| redis.architecture | string | `"standalone"` |  |
| redis.auth.password | string | `"everyone-check-fish-kind-language"` |  |
| redis.auth.sentinel | bool | `false` |  |
| redis.enabled | bool | `true` | Enable preconfigured redis configuration |
| redis.master.resourcesPreset | string | `"medium"` |  |
| redis.master.revisionHistoryLimit | int | `2` |  |
