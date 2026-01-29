# Inference Infrastructure

Umbrella chart that installs the infrastructure layer for the LLM inference platform.

## Overview

This chart bundles infrastructure components for the LLM inference platform:

| Component | Description |
|-----------|-------------|
| networking-layer | Envoy Gateway + Kourier |
| litellm-proxy | LiteLLM multi-tenant API proxy |

> **Note:** PostgreSQL and Valkey must be deployed separately using upstream charts.
> See the "Standalone Database Deployment" section below.

## Architecture

```
                        External Traffic
                              |
                              v
                    +-------------------+
                    |  Envoy Gateway    |  (networking-layer)
                    +-------------------+
                              |
              +---------------+---------------+
              |                               |
              v                               v
    +-------------------+           +-------------------+
    |  LiteLLM Proxy    |           |     Kourier       |
    +-------------------+           +-------------------+
              |                               |
              v                               v
    +-------------------+           +-------------------+
    |   PostgreSQL +    |           |  Knative Services |
    |     Valkey        |           +-------------------+
    +-------------------+
     (standalone deploy)
```

## Prerequisites

- Kubernetes 1.25+
- Helm 3.8+
- inference-operators chart installed (CRDs)
- CloudNativePG operator installed

```bash
# Install CNPG operator
kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/main/releases/cnpg-1.26.0.yaml
```

## Database Deployment (Required Prerequisite)

Deploy PostgreSQL and Valkey separately using upstream charts before installing this chart.

This approach provides:

- **Direct version control** - Update database versions independently
- **Better flexibility** - Full access to all upstream chart options
- **Independent lifecycle** - Scale and manage databases separately from the platform
- **Simpler debugging** - Standard chart names match documentation

### Step 1: Deploy PostgreSQL (CloudNativePG)

```bash
# Add CNPG Helm repository
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update

# Install PostgreSQL cluster with connection pooling
# Release name "postgresql" creates service "postgresql-pooler-rw"
helm install postgresql cnpg/cluster -n llm-platform \
  --set cluster.instances=3 \
  --set cluster.storage.size=50Gi \
  --set cluster.storage.storageClass=gp3 \
  --set pooler.enabled=true \
  --set pooler.type=rw \
  --set pooler.poolMode=transaction \
  --set pooler.instances=2

# Verify deployment
kubectl get cluster -n llm-platform
kubectl get pods -n llm-platform -l cnpg.io/cluster=postgresql
```

### Step 2: Deploy Valkey (Redis-compatible cache)

```bash
# Add Bitnami Helm repository
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Install Valkey with Sentinel for HA
# Release name "valkey" creates service "valkey"
helm install valkey bitnami/valkey -n llm-platform \
  --set architecture=replication \
  --set sentinel.enabled=true \
  --set sentinel.quorum=2 \
  --set replica.replicaCount=2

# Verify deployment
kubectl get pods -n llm-platform -l app.kubernetes.io/name=valkey
```

### Step 3: Deploy Infrastructure (networking + LiteLLM)

```bash
# Install infrastructure with standalone database defaults
helm install infra ./charts/inference-infrastructure \
  --namespace llm-platform

# The defaults work with the release names above:
# - PostgreSQL: postgresql -> service: postgresql-pooler-rw
# - Valkey: valkey -> service: valkey
```

### Service Naming Reference

When using standalone deployment with the recommended release names:

| Service | Release Name | Service Name | Secret Name |
|---------|--------------|--------------|-------------|
| PostgreSQL pooler | `postgresql` | `postgresql-pooler-rw` | `postgresql-app` |
| PostgreSQL primary | `postgresql` | `postgresql-rw` | `postgresql-app` |
| Valkey sentinel | `valkey` | `valkey` | `valkey` |
| Valkey master | `valkey` | `valkey-master` | `valkey` |

### Custom Release Names

If using different release names, override the litellm-proxy connection settings:

```bash
# Example with custom release names
helm install infra ./charts/inference-infrastructure \
  --namespace llm-platform \
  --set litellm-proxy.database.host=mydb-pooler-rw \
  --set litellm-proxy.database.passwordSecretName=mydb-app \
  --set litellm-proxy.cache.sentinel.host=mycache \
  --set litellm-proxy.cache.passwordSecretName=mycache
```

Or via values file:

```yaml
# values-custom-db.yaml
litellm-proxy:
  database:
    host: "mydb-pooler-rw"
    passwordSecretName: "mydb-app"
  cache:
    sentinel:
      host: "mycache"
    passwordSecretName: "mycache"
```

## Quick Start

Complete deployment steps:

```bash
# 1. Create namespace
kubectl create namespace llm-platform

# 2. Install CNPG operator (if not already installed)
kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/main/releases/cnpg-1.26.0.yaml

# 3. Deploy PostgreSQL
helm install postgresql cnpg/cluster -n llm-platform \
  --set cluster.instances=3 \
  --set cluster.storage.size=50Gi \
  --set pooler.enabled=true

# 4. Deploy Valkey
helm install valkey bitnami/valkey -n llm-platform \
  --set architecture=replication \
  --set sentinel.enabled=true

# 5. Create LiteLLM secrets
kubectl create secret generic litellm-master-key \
  --namespace llm-platform \
  --from-literal=master-key="sk-$(openssl rand -hex 16)"

kubectl create secret generic litellm-salt-key \
  --namespace llm-platform \
  --from-literal=salt-key="$(openssl rand -hex 16)"

# 6. Deploy infrastructure (networking + LiteLLM)
helm install infra ./charts/inference-infrastructure \
  --namespace llm-platform \
  --set litellm-proxy.masterKey.existingSecret=litellm-master-key \
  --set litellm-proxy.masterKey.existingSecretKey=master-key \
  --set litellm-proxy.saltKey.existingSecret=litellm-salt-key \
  --set litellm-proxy.saltKey.existingSecretKey=salt-key

# 7. Verify deployment
kubectl get pods -n llm-platform
kubectl get cluster -n llm-platform
```

## Values

### Global Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `global.namespace` | string | `""` | Namespace for FQDN generation (defaults to release namespace) |

### Networking Layer

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `networking-layer.enabled` | bool | `true` | Enable networking layer |
| `networking-layer.envoyGateway.enabled` | bool | `true` | Deploy Envoy Gateway |
| `networking-layer.kourier.enabled` | bool | `true` | Deploy Kourier for Knative |

### LiteLLM Proxy

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `litellm-proxy.enabled` | bool | `true` | Enable LiteLLM proxy |
| `litellm-proxy.database.host` | string | `"postgresql-pooler-rw"` | PostgreSQL host (standalone default) |
| `litellm-proxy.database.passwordSecretName` | string | `"postgresql-app"` | PostgreSQL password secret |
| `litellm-proxy.cache.sentinel.host` | string | `"valkey"` | Valkey sentinel host (standalone default) |
| `litellm-proxy.cache.passwordSecretName` | string | `"valkey"` | Valkey password secret |

## Secrets Configuration

LiteLLM requires master key and salt key secrets. Create before installation:

```bash
# Create master key secret
kubectl create secret generic litellm-master-key \
  --namespace llm-platform \
  --from-literal=master-key="sk-your-master-key"

# Create salt key secret
kubectl create secret generic litellm-salt-key \
  --namespace llm-platform \
  --from-literal=salt-key="your-salt-key"
```

Then configure in values:

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
  --namespace llm-platform \
  --set infrastructureReleaseName=infra
```

This allows inference-stack to discover infrastructure services.

## Troubleshooting

### PostgreSQL cluster not ready (Standalone)

```bash
kubectl describe cluster postgresql -n llm-platform
kubectl logs -n llm-platform -l cnpg.io/cluster=postgresql
```

### LiteLLM cannot connect to database

```bash
# Check if pooler is running (standalone)
kubectl get pods -n llm-platform -l cnpg.io/poolerName=postgresql-pooler

# Verify secret exists (standalone)
kubectl get secret postgresql-app -n llm-platform

# Check LiteLLM logs
kubectl logs -n llm-platform -l app.kubernetes.io/name=litellm-proxy
```

### Valkey connection issues

```bash
# Check Valkey pods
kubectl get pods -n llm-platform -l app.kubernetes.io/name=valkey

# Get password from secret
VALKEY_PASSWORD=$(kubectl get secret valkey -n llm-platform -o jsonpath='{.data.valkey-password}' | base64 -d)

# Verify sentinel is working
kubectl exec -it valkey-node-0 -n llm-platform -- \
  valkey-cli -a $VALKEY_PASSWORD SENTINEL masters
```

### Service discovery issues

Verify services exist with expected names:

```bash
# Check database services
kubectl get svc -n llm-platform | grep -E "(postgresql|valkey)"

# Expected output:
# postgresql-pooler-rw   ClusterIP   ...
# postgresql-r           ClusterIP   ...
# postgresql-ro          ClusterIP   ...
# postgresql-rw          ClusterIP   ...
# valkey                 ClusterIP   ...
# valkey-headless        ClusterIP   ...
# valkey-master          ClusterIP   ...
```
