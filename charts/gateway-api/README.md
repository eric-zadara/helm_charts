# Gateway API CRDs

Helm chart for installing Gateway API Custom Resource Definitions.

## Overview

This chart installs the Gateway API CRDs required for Kubernetes-native HTTP routing:

- **GatewayClass** - Defines a class of Gateways with shared configuration
- **Gateway** - Manages load balancers and listeners
- **HTTPRoute** - Routes HTTP traffic to backend services
- **GRPCRoute** - Routes gRPC traffic to backend services
- **ReferenceGrant** - Enables cross-namespace references
- **BackendTLSPolicy** - Configures TLS for backend connections

**Version:** 1.4.1 (pinned from upstream Gateway API release)

## Prerequisites

- Kubernetes 1.25+
- Helm 3.10+
- Cluster admin permissions (for CRD installation)

## Installation

```bash
helm install gateway-api ./charts/gateway-api
```

Verify installation:

```bash
kubectl get crd | grep gateway.networking.k8s.io
```

Expected output:

```
backendtlspolicies.gateway.networking.k8s.io
gatewayclasses.gateway.networking.k8s.io
gateways.gateway.networking.k8s.io
grpcroutes.gateway.networking.k8s.io
httproutes.gateway.networking.k8s.io
referencegrants.gateway.networking.k8s.io
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `skipIfExists` | bool | `false` | Skip CRD installation if already exists |
| `keepOnUninstall` | bool | `true` | Preserve CRDs on helm uninstall (prevents data loss) |

## Upgrading

CRDs are upgraded in-place when the chart version changes. Existing Gateway resources are preserved.

```bash
helm upgrade gateway-api ./charts/gateway-api
```

## Uninstalling

**Warning:** Uninstalling with `keepOnUninstall: false` will delete all Gateway resources.

```bash
# Safe uninstall (keeps CRDs)
helm uninstall gateway-api

# Force CRD deletion (DANGER: deletes all Gateway/HTTPRoute resources)
helm uninstall gateway-api --set keepOnUninstall=false
```

## Troubleshooting

**CRDs not appearing:**

```bash
kubectl get crd | grep gateway
kubectl describe crd gateways.gateway.networking.k8s.io
```

**Version mismatch:**

```bash
kubectl get crd gateways.gateway.networking.k8s.io -o jsonpath='{.spec.versions[*].name}'
```

**Helm hook failures:**

```bash
kubectl get jobs -A | grep gateway-api
kubectl logs -n <namespace> job/<job-name>
```
