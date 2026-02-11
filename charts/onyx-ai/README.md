# Onyx AI

Batteries-included Helm chart for [Onyx](https://github.com/onyx-dot-app/onyx), an AI-powered RAG search engine, bundled with HA PostgreSQL, S3-compatible object storage, and Redis-compatible caching.

## What's Included

| Component | Chart | Description |
|-----------|-------|-------------|
| Onyx | `onyx` (upstream) | API server, web server, background workers, Vespa search engine |
| PostgreSQL | `cluster` (CNPG, aliased `postgresql-cluster`) | HA PostgreSQL via CloudNative-PG operator |
| Object Storage | `garage` (GarageFS) | Lightweight S3-compatible storage for document files |
| Redis/Cache | `valkey` (Bitnami) | Redis-compatible cache and Celery task queue backend |

## Prerequisites

- Kubernetes 1.25+
- Helm 3.8+
- CNPG operator installed cluster-wide (install via `inference-operators` chart or standalone from [cloudnative-pg.io](https://cloudnative-pg.io))

## Quick Start

```bash
helm install onyx-ai charts/onyx-ai \
  --set ingress.enabled=true \
  --set ingress.host=onyx.lab.local
```

All internal wiring (database hosts, Redis endpoints, S3 credentials, auth secrets) is pre-configured. No additional values are required when using the release name `onyx-ai`.

Verify the deployment:

```bash
kubectl get pods -l app.kubernetes.io/instance=onyx-ai
```

Access without ingress via port-forward:

```bash
kubectl port-forward svc/onyx-ai-onyx-api-service 8080:8080
kubectl port-forward svc/onyx-ai-onyx-webserver 3000:3000
# Web UI at http://localhost:3000
```

## Release Name Convention

All default values are wired for the release name `onyx-ai`. If you use a different release name, you must override the internal wiring values. The chart NOTES.txt will warn you and print the exact overrides needed.

For a custom release name (e.g., `my-onyx`):

```bash
helm install my-onyx charts/onyx-ai \
  --set onyx.configMap.POSTGRES_HOST=my-onyx-postgresql-cluster-rw \
  --set onyx.configMap.REDIS_HOST=my-onyx-valkey-primary \
  --set onyx.configMap.S3_ENDPOINT_URL=http://my-onyx-garage:3900 \
  --set onyx.configMap.S3_FILE_STORE_BUCKET_NAME=my-onyx-files \
  --set onyx.auth.postgresql.existingSecret=my-onyx-postgresql-cluster-superuser \
  --set onyx.auth.redis.existingSecret=my-onyx-valkey \
  --set onyx.auth.objectstorage.existingSecret=my-onyx-garage-credentials \
  --set garage.clusterConfig.buckets[0].name=my-onyx-files \
  --set garage.clusterConfig.keys.onyx.secretName=my-onyx-garage-credentials \
  --set garage.clusterConfig.keys.onyx.buckets[0]=my-onyx-files
```

## Ingress Configuration

Two ingress modes are available, both currently requiring Traefik:

### IngressRoute (default)

Uses the Traefik `IngressRoute` CRD for native Traefik features (middleware, certResolver):

```yaml
ingress:
  enabled: true
  type: ingressroute      # default
  host: onyx.example.com
```

### Standard Kubernetes Ingress

Uses standard `networking.k8s.io/v1` Ingress resources with Traefik annotations:

```yaml
ingress:
  enabled: true
  type: ingress
  host: onyx.example.com
  className: traefik
```

Both modes split traffic between the API server (`/api` -> port 8080) and web server (`/` -> port 3000), with automatic `/api` prefix stripping via Traefik middleware.

## Key Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `ingress.enabled` | bool | `false` | Create ingress resources |
| `ingress.host` | string | `""` | Hostname (required when ingress enabled) |
| `ingress.type` | string | `ingressroute` | `ingressroute` (Traefik CRD) or `ingress` (standard) |
| `ingress.className` | string | `traefik` | Ingress class (standard Ingress mode only) |
| `ingress.tls.enabled` | bool | `false` | Enable TLS termination |
| `ingress.tls.secretName` | string | `""` | TLS secret (cert-manager or pre-created) |
| `ingress.tls.certResolver` | string | `""` | Traefik ACME certResolver (IngressRoute only) |
| `ingress.tls.hsts.enabled` | bool | `false` | Add HSTS security headers |
| `garage.enabled` | bool | `true` | Deploy built-in GarageFS object storage |
| `cnpg.enabled` | bool | `true` | Deploy CNPG-managed PostgreSQL cluster |
| `cnpg.instances` | int | `3` | PostgreSQL instances (1 primary + N-1 replicas) |
| `redis.enabled` | bool | `true` | Deploy Bitnami Valkey (Redis-compatible) |
| `onyx.configMap.POSTGRES_HOST` | string | `onyx-ai-postgresql-cluster-rw` | PostgreSQL hostname |
| `onyx.configMap.REDIS_HOST` | string | `onyx-ai-valkey-primary` | Redis hostname |
| `onyx.configMap.S3_ENDPOINT_URL` | string | `http://onyx-ai-garage:3900` | S3 endpoint |
| `onyx.auth.postgresql.existingSecret` | string | `onyx-ai-postgresql-cluster-superuser` | PostgreSQL credentials secret |
| `onyx.auth.redis.existingSecret` | string | `onyx-ai-valkey` | Redis credentials secret |
| `onyx.auth.objectstorage.existingSecret` | string | `onyx-ai-garage-credentials` | S3 credentials secret |

See `values.yaml` for the full set of configuration options including CNPG pooler settings, resource limits, and subchart passthroughs.

## TLS / HTTPS

### With cert-manager

```yaml
ingress:
  enabled: true
  host: onyx.example.com
  tls:
    enabled: true
    secretName: onyx-tls-secret  # cert-manager Certificate target
```

### With Traefik ACME (IngressRoute only)

```yaml
ingress:
  enabled: true
  type: ingressroute
  host: onyx.example.com
  tls:
    enabled: true
    certResolver: letsencrypt-prod
```

### HSTS Headers

```yaml
ingress:
  tls:
    enabled: true
    hsts:
      enabled: true
      maxAge: 31536000
      includeSubdomains: true
      preload: false
```

When TLS is enabled, HTTP-to-HTTPS redirect is on by default (`ingress.tls.httpRedirect: true`).

## External Services

Disable any bundled service and point to an external provider instead.

### External PostgreSQL

```yaml
cnpg:
  enabled: false

externalPostgresql:
  host: postgres.example.com
  port: 5432
  database: onyx
  existingSecret: my-pg-secret  # keys: username, password

onyx:
  configMap:
    POSTGRES_HOST: postgres.example.com
  auth:
    postgresql:
      existingSecret: my-pg-secret
```

### External Redis

```yaml
redis:
  enabled: false

externalRedis:
  host: redis.example.com
  port: 6379
  existingSecret: my-redis-secret  # key: redis_password

onyx:
  configMap:
    REDIS_HOST: redis.example.com
  auth:
    redis:
      existingSecret: my-redis-secret
      secretKeys:
        REDIS_PASSWORD: redis_password
```

### External S3

```yaml
garage:
  enabled: false

objectStorage:
  endpoint: "https://s3.amazonaws.com"
  bucket: my-onyx-bucket
  region: us-east-1
  existingSecret: my-s3-secret  # keys: s3_aws_access_key_id, s3_aws_secret_access_key

onyx:
  configMap:
    S3_ENDPOINT_URL: "https://s3.amazonaws.com"
    S3_FILE_STORE_BUCKET_NAME: my-onyx-bucket
    S3_VERIFY_SSL: "true"
    AWS_REGION_NAME: us-east-1
  auth:
    objectstorage:
      existingSecret: my-s3-secret
```

For IAM/IRSA mode (e.g., EKS with IAM roles for service accounts), set `objectStorage.useIAM: true` and `onyx.auth.objectstorage.enabled: false` instead of providing credentials.

## Troubleshooting

### S3 bucket errors ("bucket not found")

GarageFS creates buckets via a post-install Job. If the Job has not completed, Onyx pods will fail to access the bucket. Check the Job status:

```bash
kubectl get jobs -l app.kubernetes.io/instance=onyx-ai
kubectl logs job/onyx-ai-garage-config
```

### Vespa deployment namespace

Vespa hardcodes `.default.svc.cluster.local` in its service discovery (see Known Limitations below). If deploying to a non-default namespace, check for Vespa connectivity errors:

```bash
kubectl logs -l app=vespa -c vespa --tail=50
```

### PgBouncer bypass for migrations

Onyx runs Alembic migrations at startup that require direct PostgreSQL access (DDL statements can fail through PgBouncer in transaction mode). The chart defaults use the superuser secret (`*-postgresql-cluster-superuser`) which connects directly. If you see migration errors, verify `onyx.auth.postgresql.existingSecret` points to the superuser secret, not the app secret.

### Port-forward for debugging

```bash
# API server
kubectl port-forward svc/onyx-ai-onyx-api-service 8080:8080

# Web UI
kubectl port-forward svc/onyx-ai-onyx-webserver 3000:3000

# GarageFS S3 API
kubectl port-forward svc/onyx-ai-garage 3900:3900

# PostgreSQL
kubectl port-forward svc/onyx-ai-postgresql-cluster-rw 5432:5432
```

### LLM provider configuration

LLM providers (OpenAI, Anthropic, etc.) are configured through the Onyx admin web interface after deployment, not via Helm values. The `GEN_AI_*` environment variables are deprecated.

## Known Limitations

- **Vespa namespace:** The upstream Onyx chart hardcodes Vespa's internal address as `vespa-0.vespa.default.svc.cluster.local`. Deploying to any namespace other than `default` will break Vespa connectivity unless you override `VESPA_HOST` in `onyx.configMap`. This is an upstream issue.
- **Release name wiring:** Helm `values.yaml` cannot contain template expressions, so service hostnames and secret names are hardcoded for release name `onyx-ai`. Using a different release name requires manual overrides (see Release Name Convention above).
- **Dual credential configuration:** S3 and database credentials must be configured in two places (`objectStorage.*` / `externalPostgresql.*` and `onyx.auth.*`) due to Helm's values.yaml limitation. The chart validates consistency and fails with clear error messages if misconfigured.
