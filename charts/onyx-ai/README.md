# Onyx AI

Batteries-included Helm chart for [Onyx](https://github.com/onyx-dot-app/onyx), an AI-powered RAG search engine, bundled with HA PostgreSQL, S3-compatible object storage, and Redis-compatible caching.

## What's Included

| Component | Chart | Description |
|-----------|-------|-------------|
| Onyx | `onyx` (upstream, `onyx-dot-app/onyx` 0.4.40) | API server, web server, background workers |
| PostgreSQL | `cluster` (CNPG, aliased `postgresql-cluster`) | HA PostgreSQL via CloudNative-PG operator |
| Object Storage | `garage` (`datahub-local/garage-helm` 0.4.1) | Lightweight S3-compatible storage for document files (wrapper-managed bootstrap job handles bucket + key + ACL setup via the garage admin API v2) |
| Redis/Cache | `valkey` (`valkey-io/valkey-helm` 0.9.3, official) | Redis-compatible cache and Celery task queue backend |
| OpenSearch | `opensearch-cluster` (opensearch-k8s-operator, aliased `opensearch-cluster`) | Document search via operator-managed OpenSearch cluster (since 0.4.0; replaces Vespa) |
| Code Interpreter | `codeInterpreter` (upstream) | Python sandbox for code execution (enabled by default since upstream 0.4.35) |

## Prerequisites

- Kubernetes 1.25+
- Helm 3.8+
- CNPG operator installed cluster-wide (install via `inference-operators` chart or standalone from [cloudnative-pg.io](https://cloudnative-pg.io))
- opensearch-k8s-operator v3.0.2+ installed cluster-wide (install via `inference-operators` >= 0.9.0 or `argo-examples-operators` >= 0.0.15)

## Minimum Requirements

The default deployment (with all batteries-included components) requests approximately:

- **~20 CPU cores** (requests total across all pods)
- **~33 Gi memory** (requests total across all pods)
- **~132 Gi storage** (PVCs for PostgreSQL, OpenSearch, GarageFS, Valkey)

Heaviest components:

| Component | CPU Request | Memory Request |
|-----------|------------|----------------|
| OpenSearch (3 nodes) | 6 CPU | 6 Gi |
| Model Servers | 6 CPU | 6 Gi |
| PostgreSQL (3 instances) | 1.5 CPU | 3 Gi |

For dev/testing environments, reduce resources via a CI-style values file. See `ci/default-values.yaml` for a reference starting point.

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
kubectl port-forward svc/onyx-ai-api-service 8080:8080
kubectl port-forward svc/onyx-ai-webserver 3000:3000
# Web UI at http://localhost:3000
```

### Deploying with ArgoCD

This chart works with ArgoCD but requires a few specific considerations
because of how it uses Helm `lookup` for credential persistence and a
post-apply Job for garage bootstrap. **Read [docs/argocd.md](docs/argocd.md)
before deploying via ArgoCD** — it covers:

- Required `ignoreDifferences` config for the wrapper-managed credentials
  secrets (otherwise argocd regenerates passwords on every sync)
- Cluster-scoped RBAC the garage subchart needs from
  `argocd-application-controller`
- Subchart dependency fetch requirements for `argocd-repo-server`
- Sync-wave ordering and the bootstrap Job's argocd Sync hook semantics
- A copy-pasteable sample `Application` manifest with all the right
  options pre-configured

## Release Name Convention

All default values are wired for the release name `onyx-ai`. If you use a different release name, you must override the internal wiring values. The chart NOTES.txt will warn you and print the exact overrides needed.

For a custom release name (e.g., `my-onyx`):

```bash
helm install my-onyx charts/onyx-ai \
  --set onyx.configMap.POSTGRES_HOST=my-onyx-postgresql-cluster-rw \
  --set onyx.configMap.REDIS_HOST=my-onyx-valkey \
  --set onyx.configMap.S3_ENDPOINT_URL=http://my-onyx-garage:3900 \
  --set onyx.configMap.S3_FILE_STORE_BUCKET_NAME=my-onyx-files \
  --set onyx.auth.postgresql.existingSecret=my-onyx-postgresql-cluster-superuser \
  --set onyx.auth.redis.existingSecret=my-onyx-valkey-credentials \
  --set onyx.auth.objectstorage.existingSecret=my-onyx-garage-credentials \
  --set valkey.auth.usersExistingSecret=my-onyx-valkey-credentials
```

The wrapper auto-generates the valkey credentials secret and the garage
credentials secret with release-name prefixes (via Helm `lookup`), and
the bootstrap job picks up bucket creation and key import automatically
via the release-scoped bucket name `{release}-files`. No additional
`garage.*` or `valkey.auth.aclUsers.*` overrides are needed for custom
release names.

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
| `postgresql-cluster.enabled` | bool | `true` | Deploy CNPG-managed PostgreSQL cluster |
| `postgresql-cluster.cluster.instances` | int | `3` | PostgreSQL instances (1 primary + N-1 replicas) |
| `redis.enabled` | bool | `true` | Deploy Valkey via `valkey-io/valkey-helm` (Redis-compatible, no operator required) |
| `onyx.configMap.POSTGRES_HOST` | string | `onyx-ai-postgresql-cluster-rw` | PostgreSQL hostname |
| `onyx.configMap.REDIS_HOST` | string | `onyx-ai-valkey` | Redis hostname (valkey-io/valkey-helm primary service; NO `-primary` suffix) |
| `onyx.configMap.S3_ENDPOINT_URL` | string | `http://onyx-ai-garage:3900` | S3 endpoint |
| `onyx.auth.postgresql.existingSecret` | string | `onyx-ai-postgresql-cluster-superuser` | PostgreSQL credentials secret |
| `onyx.auth.redis.existingSecret` | string | `onyx-ai-valkey-credentials` | Redis credentials secret (wrapper-managed, key `default-password`) |
| `onyx.auth.objectstorage.existingSecret` | string | `onyx-ai-garage-credentials` | S3 credentials secret |

See `values.yaml` for the full set of configuration options including PostgreSQL pooler settings, resource limits, and subchart passthroughs.

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
postgresql-cluster:
  enabled: false

externalPostgresql:
  host: postgres.example.com
  port: 5432
  database: postgres  # or your database name
  existingSecret: my-pg-secret  # keys: username, password

onyx:
  configMap:
    POSTGRES_HOST: postgres.example.com
  auth:
    postgresql:
      existingSecret: my-pg-secret
```

### Connection pooling (pgbouncer)

Since 0.4.0 the chart ships a session-mode pgbouncer pooler by default. Onyx pods connect through `{release}-postgresql-cluster-pooler-rw` instead of the direct `-rw` service. This absorbs connection bursts during rolling restarts that previously caused `FATAL: sorry, too many clients already` errors at `max_connections=100` (fixed in 0.2.6 → 500, further hardened in 0.4.0 → 750 backend + 2000 client via pooler).

**Why session mode?** Alembic migrations (Onyx startup) require DDL access, which PgBouncer transaction mode blocks. Session mode pins a server connection for the client session's duration, preserving DDL semantics at the cost of not multiplexing clients onto fewer server connections. For Onyx's workload the main benefit is burst absorption and fork-cost amortization, not connection multiplexing.

**Adjusting the pooler:** Edit `postgresql-cluster.poolers[0]` in your values overlay:

```yaml
postgresql-cluster:
  poolers:
    - name: rw
      type: rw
      poolMode: session
      instances: 4                      # bump for more HA
      parameters:
        max_client_conn: "4000"          # raise the user-visible cap
        default_pool_size: "500"         # raise server-side capacity
```

**Disabling the pooler entirely:** Set `postgresql-cluster.poolers: []` AND override `onyx.configMap.POSTGRES_HOST` to `"{release}-postgresql-cluster-rw"`. The chart's validation helper will fail render if only one of the two is done.

**Adding a read-only pooler for analytics workloads:** Append a second entry with `type: ro` and route analytics clients at `{release}-postgresql-cluster-pooler-ro`. The main onyx pods continue to use the `rw` pooler.

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

### Redis HA Mode (Spotahome Redis Operator)

The chart supports HA Redis via the Spotahome Redis Operator (RedisFailover CRD). This requires the operator to be pre-installed in the cluster.

Three Redis modes are available:
1. **Valkey standalone** (default) -- valkey-io/valkey-helm, no operator required
2. **Spotahome HA** -- RedisFailover with Sentinels for automatic failover
3. **External** -- connect to an existing Redis/Valkey instance

To enable Redis HA mode:

```yaml
redis:
  enabled: false  # Disable Valkey
  ha:
    enabled: true
    replicas: 3
    sentinels: 3

onyx:
  redis:
    enabled: false
  configMap:
    REDIS_HOST: "rfr-{release}-redis-ha"
  auth:
    redis:
      existingSecret: "{fullname}-redis-ha"
      secretKeys:
        REDIS_PASSWORD: redis_password
```

Replace `{release}` with your Helm release name and `{fullname}` with the Helm fullname
(when the release name contains the chart name "onyx-ai", fullname = release name, e.g., `onyx-ai`).

**Migrating from Valkey to HA mode:**

1. Drain the Celery task queue (wait for running tasks to complete)
2. Scale down Onyx workers: `kubectl scale deployment -l app=celery-worker --replicas=0`
3. Switch to HA mode via `helm upgrade` with the values above
4. Delete orphaned Valkey PVC: `kubectl delete pvc data-{release}-valkey-primary-0`
5. Scale workers back up

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

## OpenSearch (search backend)

Since 0.4.0 the chart ships OpenSearch managed by [opensearch-k8s-operator](https://github.com/opensearch-project/opensearch-k8s-operator) v3.0.2+ via the sibling `opensearch-cluster` convenience subchart (v3.2.2). Vespa is retired.

**Prerequisites:** the `opensearch-operator` chart must be installed cluster-wide. In this repo's stack:

- Via `inference-operators` >= 0.9.0 (helm deps path)
- Via `argo-examples-operators` >= 0.0.15 (ArgoCD app-of-apps path)

Either path installs the operator + CRDs. Without the operator, the `OpenSearchCluster` CR emitted by onyx-ai will render but not reconcile.

**Default topology:** single combined nodePool with roles `[master, data, ingest]`, 3 replicas, 30Gi per node, 2Gi/8Gi resource limits, JVM heap `3g`.

**Dedicated masters + data topology:** operators who want role separation can split the nodePool list. See `ci/opensearch-dedicated-masters-values.yaml` for a working example. Adjust `opensearch-cluster.cluster.nodePools` in your overlay:

```yaml
opensearch-cluster:
  cluster:
    nodePools:
      - component: masters
        replicas: 3
        diskSize: "10Gi"
        roles: [master]
        resources:
          requests: { cpu: 250m, memory: 1Gi }
          limits: { memory: 2Gi }
      - component: data
        replicas: 3
        diskSize: "200Gi"
        roles: [data, ingest]
        resources:
          requests: { cpu: 1000m, memory: 4Gi }
          limits: { memory: 16Gi }
```

**External OpenSearch:** set `opensearch-cluster.enabled: false` and populate `externalOpenSearch.host` / `externalOpenSearch.existingSecret`. The wrapper will skip rendering the CR and wire onyx to the external service.

**vm.max_map_count gotcha:** OpenSearch requires `vm.max_map_count >= 262144` at the kernel level. The operator installs a privileged init container per data pod (`opensearch-cluster.cluster.general.setVMMaxMapCount: true`, default). On nodes with strict PodSecurityStandards this may fail -- in that case set `setVMMaxMapCount: false` and configure the sysctl via a node-level DaemonSet or k3s node config.

**Admin credentials:** the wrapper owns a lookup-pattern secret named `{release}-opensearch-admin` with `username` / `password` keys. It persists across upgrades (no password rotation drift). Consumed by both the operator (for cluster management) and onyx (via `onyx.auth.opensearch.existingSecret`).

**Upgrading the OpenSearch version:** bump `opensearch-cluster.cluster.general.version` in your overlay. The operator drains data nodes shard-by-shard for safe rolling upgrades.

**Rollback to Vespa:** helm rollback to onyx-ai 0.2.11 restores Vespa -- the 0.2.11 values still have `onyx.vespa.enabled: true`. The `OpenSearchCluster` CR carries `helm.sh/resource-policy: keep` so it will persist as an orphan; delete manually if desired.

## Scaling / HPA

The upstream Onyx chart supports Horizontal Pod Autoscaling for the API and web servers:

```yaml
onyx:
  api:
    autoscaling:
      enabled: true
      minReplicas: 2
      maxReplicas: 5
      targetCPUUtilizationPercentage: 80
  webserver:
    autoscaling:
      enabled: true
      minReplicas: 2
      maxReplicas: 4
      targetCPUUtilizationPercentage: 80
```

When HPA is enabled, `replicaCount` is used as the initial replica count and HPA manages scaling from there.

## Monitoring

CloudNative-PG exposes Prometheus metrics natively on the PostgreSQL pods. No ServiceMonitor is created by default. To scrape metrics, configure your Prometheus instance to target the CNPG pods directly or add a PodMonitor/ServiceMonitor to your monitoring stack.

## Backups

CloudNative-PG supports automated backups to S3-compatible storage:

```yaml
postgresql-cluster:
  cluster:
    backup:
      enabled: true
      schedule: "0 0 * * *"  # Daily at midnight UTC
      retentionPolicy: "7d"
      s3:
        bucket: my-backup-bucket
        region: us-east-1
        endpoint: "https://s3.amazonaws.com"
        existingSecret: my-backup-s3-secret  # keys: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
```

This configures both scheduled backups and enables on-demand `Backup` CRD usage via CloudNative-PG.

## Secret Rotation

Auto-generated secrets (GarageFS credentials, Valkey credentials, Redis HA password) use the Helm `lookup` pattern to persist across upgrades. To rotate any of them, delete the Secret and run `helm upgrade` — the chart will regenerate it with new random values:

```bash
# Rotate the garage S3 credentials
kubectl delete secret onyx-ai-garage-credentials
# Rotate the valkey default-user password
kubectl delete secret onyx-ai-valkey-credentials
# Then re-render:
helm upgrade onyx-ai charts/onyx-ai
```

Pods referencing the rotated secret will need to be restarted to pick up the new credentials. For the valkey password, you'll also need to restart the valkey pod itself so its ACL reloads. Rotating the garage access key additionally requires the garage bootstrap job to re-run (it's a post-upgrade hook, so it runs automatically on `helm upgrade`).

If you've enabled the optional [External Secrets Operator integration](docs/argocd.md#option-2-external-secrets-operator-integration-recommended-for-production)
(`externalSecrets.enabled: true`), rotation is handled in your upstream
backend (Vault, AWS Secrets Manager, etc.) rather than by the wrapper. ESO
reconciles the new value into the K8s Secret on its next refresh interval
(default 1h, configurable via `externalSecrets.refreshInterval`). You still
need to restart pods that mount the secret as a file or environment
variable to pick up the new value.

## Troubleshooting

### S3 bucket errors ("Access Denied" or "bucket not found")

When `garage.enabled: true` the chart runs a wrapper-managed post-install
Helm hook Job (`{release}-garage-bootstrap`) that talks to garage's
admin API v2 to stage + apply cluster layout, create the bucket, import
the access key, and grant bucket-key permissions. The Job verifies the
resulting ACL before exiting — if it can't grant permissions, the helm
install fails loudly instead of leaving the chart in a broken state.

Because the Job is a post-install hook with
`hook-delete-policy: before-hook-creation,hook-succeeded`, it's
**automatically deleted on success** — if you don't see the Job, that's
normal, it completed. To inspect a failing install, check:

```bash
# List hook jobs (may be empty if the Job already succeeded and was cleaned)
kubectl -n {namespace} get jobs -l app.kubernetes.io/instance={release}

# If a failing job exists:
kubectl -n {namespace} logs job/{release}-garage-bootstrap

# Or check the bootstrap script content directly:
kubectl -n {namespace} get configmap {release}-garage-bootstrap \
  -o jsonpath='{.data.bootstrap\.py}' | less
```

The bootstrap Job runs `python:3.12-slim` with stdlib only (no pip
install). Retry / timeout tunables live under `garage.bootstrap.*` in
`values.yaml`:

| Key | Default | Purpose |
|---|---|---|
| `garage.bootstrap.readyTimeoutSeconds` | `600` | Per-phase wait (admin API reachable, cluster healthy) |
| `garage.bootstrap.stepRetries` | `30` | Per-step retry attempts |
| `garage.bootstrap.stepBackoffSeconds` | `5` | Backoff between retry attempts |
| `garage.bootstrap.capacityBytes` | `10737418240` | Per-node layout capacity in bytes (10 GiB default) |
| `garage.bootstrap.zone` | `dc1` | Layout zone label |
| `garage.bootstrap.backoffLimit` | `6` | Job-level pod restart budget |
| `garage.bootstrap.ttlSecondsAfterFinished` | `3600` | TTL for the completed Job before GC |

**Historical note:** Prior to 0.2.0 the chart relied on the upstream
`garage.clusterConfig` Job shipped by `datahub-local/garage-helm`. That
Job ran every CLI command with `|| true`, so silent failures in
`bucket allow` would leave garage's authoritative state with no
permissions on the bucket and onyx pods would crash-loop forever on
AccessDenied. The wrapper now owns this step to guarantee permissions
actually get applied, or the install fails loudly.

### OpenSearch cluster not reconciling

If the `OpenSearchCluster` CR is created but pods never appear, the opensearch-k8s-operator is likely not installed. Check:

```bash
# Operator must be running
kubectl get pods -l app.kubernetes.io/name=opensearch-k8s-operator -A

# CR status
kubectl get opensearchcluster -n {namespace} {release}-opensearch -o yaml | grep -A20 status
```

Install the operator via `inference-operators` >= 0.9.0 or `argo-examples-operators` >= 0.0.15 before retrying.

### PgBouncer bypass for migrations

Onyx runs Alembic migrations at startup that require direct PostgreSQL access (DDL statements can fail through PgBouncer in transaction mode). The chart defaults use the superuser secret (`*-postgresql-cluster-superuser`) which connects directly. If you see migration errors, verify `onyx.auth.postgresql.existingSecret` points to the superuser secret, not the app secret.

### Port-forward for debugging

```bash
# API server
kubectl port-forward svc/onyx-ai-api-service 8080:8080

# Web UI
kubectl port-forward svc/onyx-ai-webserver 3000:3000

# GarageFS S3 API
kubectl port-forward svc/onyx-ai-garage 3900:3900

# PostgreSQL
kubectl port-forward svc/onyx-ai-postgresql-cluster-rw 5432:5432
```

### LLM provider configuration

LLM providers (OpenAI, Anthropic, etc.) are configured through the Onyx admin web interface after deployment, not via Helm values. The `GEN_AI_*` environment variables are deprecated.

## Upgrade Notes

### 0.2.0 — garage bootstrap + valkey upstream swap + subchart bumps

Three major changes land together in this release:

**1. Garage bootstrap job replaces upstream `clusterConfig`.** The
`datahub-local/garage-helm` chart's built-in post-install Job ran every
garage CLI command with `|| true`, including `bucket allow`. If permission
granting silently failed (layout convergence race on multi-node, etc.) the
Job exited success but left the bucket ACL unset, and onyx pods
crash-looped forever on AccessDenied with nothing to retry against.

The wrapper now disables `garage.clusterConfig.enabled` by default and
ships its own post-install Helm hook (`garage.bootstrap`) that talks to
the garage admin API v2 directly — idempotent, no error masking,
verifies the resulting bucket-key permissions before exiting. Tunables
live under `garage.bootstrap.*` (image, retries, capacity, zone,
timeouts). See `templates/garage-bootstrap-configmap.yaml` for the
script and `templates/garage-bootstrap-job.yaml` for the Job spec.

If you were overriding `garage.clusterConfig.*` for custom setup, move
your bucket list into `garage.bootstrap` equivalents instead of
re-enabling the upstream job — the two will fight over layout
assignment if both run.

**2. Valkey dependency changed from `bitnami/valkey` to
`valkey-io/valkey-helm`.** Broadcom's Bitnami catalog went legacy in
Aug/Sept 2025 — tagged images and charts at
`charts.bitnami.com/bitnami` stopped receiving CVE fixes. The official
upstream chart maintained by the Linux Foundation Valkey project is a
drop-in replacement, BSD-3 licensed, tracks Valkey 9.x.

Resulting resource shape (all automatic when you use the default
release name `onyx-ai`):

| | Value |
|---|---|
| Primary service | `{release}-valkey` |
| Credentials secret | `{release}-valkey-credentials` (wrapper-managed, lookup-pattern) |
| Password key | `default-password` |
| Workload kind | Deployment |
| Auth model | ACL with explicit `default` user |
| Resources field | `valkey.resources` (top level) |
| Persistence field | `valkey.dataStorage.*` |

The wrapper owns the credentials secret (same Helm `lookup` pattern as
`garage-credentials-secret.yaml`) so the password persists across
upgrades — the upstream chart has no lookup logic. Both the valkey
pod and onyx pods read `default-password` from the same
`{release}-valkey-credentials` secret.

**3. Subchart versions bumped:**
- `onyx`: 0.4.35 → 0.4.40 (minor: adds `update-ca-certificates` startup flag)
- `garage`: 0.2.1 → 0.4.1 (app version v2.1.0 → v2.2.0; configure script
  is byte-identical across the bump, so the wrapper bootstrap is still
  needed)
- `onyx.global.version` pinned to `v3.1.1` (upstream defaults to
  `latest`, which we refuse to ship against for reproducibility). Bump
  in lockstep with the onyx subchart version when upgrading.

### Earlier versions

- **PgBouncer pooler disabled by default (0.1.3):** The CNPG pooler was disabled by default since POSTGRES_HOST connects directly to the `-rw` service for Alembic DDL compatibility. In 0.4.0 a session-mode pooler is re-enabled by default with DDL-safe session mode; use `postgresql-cluster.poolers: []` to disable.
- **OpenSearch auth section added (0.1.3):** The wrapper includes an explicit `onyx.auth.opensearch` section. Since 0.4.0 the wrapper owns the admin credentials secret (`{release}-opensearch-admin`) via lookup-pattern — no manual password management needed.
- **AUTH_TYPE default changed in 0.4.35:** Upstream changed `AUTH_TYPE` from `"disabled"` to `"basic"`. If you relied on the old default, explicitly set `onyx.configMap.AUTH_TYPE: "disabled"` to preserve the previous behavior.
- **PVC sizes can only increase:** Kubernetes PersistentVolumeClaims cannot be shrunk. If you need smaller volumes, delete the PVC and let it be recreated (data loss).
- **Privileged containers:** Model servers and the code-interpreter run as privileged or with elevated capabilities. Review your PodSecurityPolicy/PodSecurityStandards if running in a restricted cluster.

## Known Limitations

- **OpenSearch operator prerequisite:** The `OpenSearchCluster` CR will render but not reconcile without the opensearch-k8s-operator installed cluster-wide. See the Prerequisites section and the troubleshooting subsection above.
- **Release name wiring:** Helm `values.yaml` cannot contain template expressions, so service hostnames and secret names are hardcoded for release name `onyx-ai`. Using a different release name requires manual overrides (see Release Name Convention above).
- **Dual credential configuration:** S3 and database credentials must be configured in two places (`objectStorage.*` / `externalPostgresql.*` and `onyx.auth.*`) due to Helm's values.yaml limitation. The chart validates consistency and fails with clear error messages if misconfigured.
- **CNPG externalClusters fix:** The chart includes a template override (`_cnpg-fix.tpl`) that fixes a null value bug in the upstream CNPG cluster chart's `externalClusters` handling for standalone mode. This override may need updating when upgrading the CNPG chart dependency.
