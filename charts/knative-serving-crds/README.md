# Knative Serving CRDs

Helm chart for installing Knative Serving Custom Resource Definitions.

## Overview

This chart installs the Knative Serving CRDs required for serverless workload management:

**Core CRDs (serving.knative.dev):**
- **Service** - Top-level resource for deploying serverless workloads
- **Configuration** - Describes desired state for a revision
- **Revision** - Immutable snapshot of application code and configuration
- **Route** - Routes traffic to revisions

**Networking CRDs (networking.internal.knative.dev):**
- **Ingress** - Internal ingress representation
- **Certificate** - TLS certificate management
- **ServerlessService** - Internal service abstraction
- **ClusterDomainClaim** - Domain name claims

**Autoscaling CRDs (autoscaling.internal.knative.dev):**
- **PodAutoscaler** - Knative Pod Autoscaler (KPA) resource
- **Metric** - Autoscaling metrics

**Caching CRDs (caching.internal.knative.dev):**
- **Image** - Container image caching

**Version:** 1.20.1 (pinned from upstream Knative Serving release)

## Prerequisites

- Kubernetes 1.25+
- Helm 3.10+
- Cluster admin permissions (for CRD installation)

## Installation

```bash
helm install knative-serving-crds ./charts/knative-serving-crds
```

Verify installation:

```bash
kubectl get crd | grep knative.dev
```

Expected output:

```
certificates.networking.internal.knative.dev
clusterdomainclaims.networking.internal.knative.dev
configurations.serving.knative.dev
domainmappings.serving.knative.dev
images.caching.internal.knative.dev
ingresses.networking.internal.knative.dev
metrics.autoscaling.internal.knative.dev
podautoscalers.autoscaling.internal.knative.dev
revisions.serving.knative.dev
routes.serving.knative.dev
serverlessservices.networking.internal.knative.dev
services.serving.knative.dev
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `skipIfExists` | bool | `false` | Skip CRD installation if already exists |
| `keepOnUninstall` | bool | `true` | Preserve CRDs on helm uninstall (prevents data loss) |

## Upgrading

CRDs are upgraded in-place when the chart version changes. Existing Knative Service resources are preserved.

```bash
helm upgrade knative-serving-crds ./charts/knative-serving-crds
```

## Uninstalling

**Warning:** Uninstalling with `keepOnUninstall: false` will delete all Knative Service resources.

```bash
# Safe uninstall (keeps CRDs)
helm uninstall knative-serving-crds

# Force CRD deletion (DANGER: deletes all Knative Service/Revision resources)
helm uninstall knative-serving-crds --set keepOnUninstall=false
```

## Troubleshooting

**CRDs not appearing:**

```bash
kubectl get crd | grep knative
kubectl describe crd services.serving.knative.dev
```

**Version verification:**

```bash
kubectl get crd services.serving.knative.dev -o jsonpath='{.spec.versions[*].name}'
```

**Service stuck in Unknown status:**

```bash
kubectl get ksvc -A
kubectl describe ksvc <name> -n <namespace>
```
