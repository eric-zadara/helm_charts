# Inference Infrastructure

Umbrella chart for LLM inference platform infrastructure with zero-config deployment.

## What's Included

| Component | Description | Default |
|-----------|-------------|---------|
| PostgreSQL | CNPG cluster with PgBouncer pooling | Enabled |
| Valkey | Redis-compatible cache | Enabled |
| Networking | Envoy Gateway + Kourier | Enabled |
| LiteLLM | Multi-tenant API proxy | Enabled |

All components are toggleable. Disable any component and provide external endpoints.

## Architecture

```
                    External Traffic
                          |
                          v
                +-------------------+
                |  Envoy Gateway    |
                +-------------------+
                          |
          +---------------+---------------+
          |                               |
          v                               v
+-------------------+           +-------------------+
|  LiteLLM Proxy    |           |     Kourier       |
+-------------------+           +-------------------+
      |           |                       |
      v           v                       v
+-----------+  +----------+     +-------------------+
| PostgreSQL|  |  Valkey  |     |  Knative Services |
|  (CNPG)   |  |          |     +-------------------+
+-----------+  +----------+
```

## Prerequisites

- Kubernetes 1.25+
- Helm 3.8+
- inference-operators chart installed (provides CNPG operator + CRDs)

## Zero-Config Deployment

Three commands to deploy a complete inference platform:

```bash
# 1. Install operators (CNPG operator + CRDs)
helm install operators ./charts/inference-operators

# 2. Install infrastructure (PostgreSQL + Valkey + Networking + LiteLLM)
helm install infra ./charts/inference-infrastructure

# 3. Install model serving stack
helm install stack ./charts/inference-stack --set infrastructureReleaseName=infra
```

Verify the deployment:

```bash
# Check all pods are running
kubectl get pods

# Check PostgreSQL cluster is ready
kubectl get cluster

# Check LiteLLM is connected
kubectl logs -l app.kubernetes.io/name=litellm-proxy | head -20
```

LiteLLM automatically connects to the deployed PostgreSQL and Valkey using the release name convention.

## Service Naming Convention

When using release name `infra`, these services are created:

| Service | Name | Description |
|---------|------|-------------|
| PostgreSQL pooler | `infra-postgresql-pooler-rw` | PgBouncer connection pooler |
| PostgreSQL secret | `infra-postgresql-app` | Database credentials |
| Valkey service | `infra-valkey` | Redis-compatible cache |
| Valkey auth secret | `infra-valkey-auth` | Cache credentials |

LiteLLM is pre-configured to connect to these services automatically.

## Values

### Database Components

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `postgresql.enabled` | bool | `true` | Deploy PostgreSQL cluster |
| `postgresql.cluster.instances` | int | `3` | Number of PostgreSQL instances |
| `postgresql.cluster.storage.size` | string | `50Gi` | Storage per instance |
| `postgresql.poolers[0].instances` | int | `2` | Number of PgBouncer instances |
| `valkey.enabled` | bool | `true` | Deploy Valkey cache |
| `valkey.replica.replicaCount` | int | `2` | Number of Valkey replicas |

### Networking Components

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `networking-layer.enabled` | bool | `true` | Deploy networking layer |
| `networking-layer.envoyGateway.enabled` | bool | `true` | Deploy Envoy Gateway |
| `networking-layer.kourier.enabled` | bool | `true` | Deploy Kourier for Knative |

### LiteLLM Proxy

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `litellm-proxy.enabled` | bool | `true` | Deploy LiteLLM proxy |
| `litellm-proxy.database.host` | string | `infra-postgresql-pooler-rw` | PostgreSQL host |
| `litellm-proxy.database.passwordSecretName` | string | `infra-postgresql-app` | PostgreSQL secret |
| `litellm-proxy.cache.host` | string | `infra-valkey` | Valkey host |
| `litellm-proxy.cache.passwordSecretName` | string | `infra-valkey-auth` | Valkey secret |

## Using External Databases

Disable bundled databases and provide external endpoints:

```yaml
# values-external-db.yaml
postgresql:
  enabled: false

valkey:
  enabled: false

litellm-proxy:
  database:
    host: "my-external-postgresql.database.svc.cluster.local"
    port: 5432
    name: "litellm"
    user: "litellm"
    passwordSecretName: "my-postgres-secret"
    passwordSecretKey: "password"
  cache:
    host: "my-external-redis.cache.svc.cluster.local"
    port: 6379
    passwordSecretName: "my-redis-secret"
    passwordSecretKey: "password"
```

```bash
helm install infra ./charts/inference-infrastructure -f values-external-db.yaml
```

### External Database with Sentinel

For Redis/Valkey clusters with Sentinel:

```yaml
litellm-proxy:
  cache:
    sentinel:
      enabled: true
      host: "my-sentinel.cache.svc.cluster.local"
      port: 26379
      masterName: "mymaster"
    passwordSecretName: "my-redis-secret"
    passwordSecretKey: "password"
```

## Custom Release Names

If using a different release name, update the LiteLLM connection settings:

```bash
# Example: release name "platform" instead of "infra"
helm install platform ./charts/inference-infrastructure \
  --set litellm-proxy.database.host=platform-postgresql-pooler-rw \
  --set litellm-proxy.database.passwordSecretName=platform-postgresql-app \
  --set litellm-proxy.cache.host=platform-valkey \
  --set litellm-proxy.cache.passwordSecretName=platform-valkey-auth
```

## Secrets Configuration

LiteLLM requires master key and salt key secrets for API authentication:

```bash
# Create master key secret
kubectl create secret generic litellm-master-key \
  --from-literal=master-key="sk-$(openssl rand -hex 16)"

# Create salt key secret
kubectl create secret generic litellm-salt-key \
  --from-literal=salt-key="$(openssl rand -hex 16)"
```

Configure in values:

```yaml
litellm-proxy:
  masterKey:
    existingSecret: "litellm-master-key"
    existingSecretKey: "master-key"
  saltKey:
    existingSecret: "litellm-salt-key"
    existingSecretKey: "salt-key"
```

## Usage with inference-stack

After installing inference-infrastructure, install inference-stack:

```bash
helm install stack ./charts/inference-stack \
  --set infrastructureReleaseName=infra
```

This allows inference-stack to discover infrastructure services.

## Troubleshooting

### CNPG Cluster Not Ready

```bash
# Check cluster status
kubectl describe cluster infra-postgresql

# Check CNPG operator logs
kubectl logs -l app.kubernetes.io/name=cloudnative-pg

# Check PostgreSQL instance logs
kubectl logs -l cnpg.io/cluster=infra-postgresql
```

Common issues:
- **Pending PVC**: Check storage class exists and has available capacity
- **Operator not running**: Ensure inference-operators was installed first

### PostgreSQL Pooler Connection Issues

```bash
# Check pooler pods are running
kubectl get pods -l cnpg.io/poolerName=infra-postgresql-pooler

# Check pooler logs
kubectl logs -l cnpg.io/poolerName=infra-postgresql-pooler

# Verify secret exists
kubectl get secret infra-postgresql-app
```

### Valkey Connection Issues

```bash
# Check Valkey pods
kubectl get pods -l app.kubernetes.io/name=valkey

# Test connection
kubectl exec -it deploy/infra-valkey-primary -- valkey-cli -a $(kubectl get secret infra-valkey-auth -o jsonpath='{.data.default-password}' | base64 -d) PING
```

### LiteLLM Cannot Connect to Database

```bash
# Check LiteLLM logs
kubectl logs -l app.kubernetes.io/name=litellm-proxy

# Verify database connectivity from LiteLLM pod
kubectl exec -it deploy/infra-litellm-proxy -- \
  nc -zv infra-postgresql-pooler-rw 5432
```

Common issues:
- **Connection refused**: Pooler not ready yet. Wait for cluster to be fully initialized.
- **Authentication failed**: Check that secret names match between PostgreSQL and LiteLLM config.
- **Database does not exist**: Migration job may have failed. Check job logs.

### Service Discovery Issues

Verify services exist with expected names:

```bash
# Check database services
kubectl get svc | grep -E "(postgresql|valkey)"

# Expected output for release name "infra":
# infra-postgresql-pooler-rw   ClusterIP   ...
# infra-postgresql-r           ClusterIP   ...
# infra-postgresql-ro          ClusterIP   ...
# infra-postgresql-rw          ClusterIP   ...
# infra-valkey                 ClusterIP   ...
```

### Migration Job Failed

```bash
# Check migration job status
kubectl get jobs | grep litellm

# Check migration logs
kubectl logs job/infra-litellm-proxy-migration
```
