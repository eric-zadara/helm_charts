# llama-cpp-server

Helm chart for deploying [llama.cpp](https://github.com/ggml-org/llama.cpp) server on Kubernetes.

## Overview

This chart deploys `llama-server` from the llama.cpp project as a Kubernetes workload. It provides:

- **OpenAI-compatible API** (`/v1/chat/completions`, `/v1/completions`, `/v1/embeddings`)
- **GPU and CPU support** with automatic image selection for NVIDIA, AMD, Intel, and Vulkan
- **Multi-model routing** to serve multiple GGUF models from a single deployment
- **GGUF format** support with flexible model loading from PVC, HuggingFace, URL, or S3
- **Serverless scaling** via optional Knative Serving integration
- **Prometheus monitoring** via `/metrics` endpoint and ServiceMonitor
- **Input validation** with clear error messages for misconfigured required fields

## Prerequisites

- Kubernetes 1.26+
- Helm 3+
- **Optional**: [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/) for GPU workloads
- **Optional**: [Knative Serving](https://knative.dev/docs/serving/) for serverless scale-to-zero
- **Optional**: [Prometheus Operator](https://prometheus-operator.dev/) for ServiceMonitor support

## Installation

```bash
helm install my-llama ./charts/llama-cpp-server -f values.yaml
```

To install with a custom values file:

```bash
helm install my-llama ./charts/llama-cpp-server \
  --set gpu.enabled=true \
  --set model.source=hf \
  --set model.hf.repo=ggml-org/Qwen2.5-3B-Instruct-GGUF \
  --set model.preload=true \
  --set model.hf.file=qwen2.5-3b-instruct-q4_k_m.gguf
```

## Upgrade Notes

- **Switching between Deployment and Knative**: Toggling `knative.enabled` via `helm upgrade` will leave the old resource (Deployment or Knative Service) orphaned. Use `helm uninstall` followed by `helm install` when changing this setting.
- **PVC immutable fields**: `persistentVolume.storageClass` and `persistentVolume.accessModes` cannot be changed after the PVC is created. To modify these, delete the existing PVC first (this will cause data loss).
- **Model file caching**: When `preload: true`, the init container skips the download if a file already exists at the target path. Changing `model.source` or `model.url` will not replace an existing file. To force a re-download, delete the model file from the PVC or use a different model name.
- **Multi-architecture**: The chart does not restrict node architecture. If deploying on ARM64 nodes, verify that the llama.cpp container image supports your architecture and add a `nodeSelector` (e.g., `kubernetes.io/arch: amd64`) as needed.
- **Pod Security Standards**: The init container runs as `root` (`runAsUser: 0`) to install download tools via `apk`. This is incompatible with the PSA `restricted` profile. Clusters enforcing `restricted` Pod Security Standards must either use the `baseline` profile or grant an exemption for this namespace.
- **Service type immutability**: Kubernetes does not allow changing `service.type` (e.g., ClusterIP → LoadBalancer) via `helm upgrade`. Delete the Service first or use `helm uninstall` + `helm install`.
- **Knative feature flags**: Enabling `knative.enabled` requires the cluster to have `kubernetes.podspec-persistent-volume-claim` and `kubernetes.podspec-init-containers` Knative feature flags enabled. Without these, pods will fail with confusing "not supported" errors from the Knative controller.
- **Release name immutability**: The Deployment's `spec.selector.matchLabels` is immutable. Changing the release name (or `nameOverride`/`fullnameOverride`) after initial install will fail on `helm upgrade`. Use `helm uninstall` + `helm install` if you need to rename.

## GPU Support

Enable GPU acceleration by setting `gpu.enabled: true`. The chart automatically selects the correct container image and injects the appropriate resource limits.

| `gpu.type` | Image Tag        | Resource Key            |
|------------|------------------|-------------------------|
| `nvidia`   | `server-cuda`    | `nvidia.com/gpu`        |
| `amd`      | `server-rocm`    | `amd.com/gpu`           |
| `intel`    | `server-intel`   | `gpu.intel.com/i915`    |
| `vulkan`   | `server-vulkan`  | _(no resource request)_ |

When `gpu.type` is `nvidia`, the chart automatically adds a toleration for the `nvidia.com/gpu` taint so pods can schedule on GPU nodes.

The image tag is computed automatically from `gpu.type` unless `image.tag` is explicitly set. With GPU disabled, the `server` (CPU-only) image is used.

Resource key overrides are available for MIG or custom device plugins via `gpu.nvidiaResource`, `gpu.amdResource`, and `gpu.intelResource`. For Vulkan, no standard Kubernetes device-plugin resource key exists; set `gpu.vulkanResource` if your cluster exposes one, or use `nodeSelector`/`tolerations` for scheduling.

```yaml
gpu:
  enabled: true
  type: nvidia
  count: 1
```

## Model Loading

There are three ways to provide a model to the server.

### 1. PVC with Pre-Loaded Model (Default)

Point `model.path` to a GGUF file that already exists on the persistent volume:

```yaml
model:
  path: /models/my-model.gguf
persistentVolume:
  existingClaim: my-models-pvc
```

### 2. HuggingFace Download (Server-Side)

When `model.source` is set to `hf` and `model.preload` is `false`, the server downloads the model directly on startup using the `--hf-repo` flag:

```yaml
model:
  source: hf
  hf:
    repo: "ggml-org/Qwen2.5-3B-Instruct-GGUF"
    file: "qwen2.5-3b-instruct-q4_k_m.gguf"
```

### 3. Preload Init Container

Set `model.preload: true` to download the model in an init container before the server starts. This supports `hf`, `url`, and `s3` sources.

**Important**: When using preload with HuggingFace source, `model.hf.file` is required so the init container knows which file to download.

```yaml
# HuggingFace preload
model:
  source: hf
  hf:
    repo: "ggml-org/Qwen2.5-3B-Instruct-GGUF"
    file: "qwen2.5-3b-instruct-q4_k_m.gguf"
  preload: true

# Direct URL preload
model:
  source: url
  url: "https://example.com/model.gguf"
  preload: true

# S3 preload
model:
  source: s3
  s3:
    bucket: my-models
    key: models/model.gguf
    region: us-east-1
  preload: true
```

**S3 retries**: The init container sets `AWS_MAX_ATTEMPTS=3` for retry resilience on S3 downloads. This value is hardcoded and not user-configurable.

For private repositories, provide credentials via an existing Kubernetes secret:

```yaml
model:
  credentials:
    existingSecret: my-hf-secret
    secretKeys:
      HF_TOKEN: "token"
```

## Authentication

API key authentication is handled via the `LLAMA_API_KEY` environment variable (not a CLI argument). The recommended approach for production is to store the key in a Kubernetes Secret:

```yaml
server:
  apiKeySecret: my-llama-api-key-secret   # Secret must contain key "api-key"
```

For development or testing, you can set the key directly (not recommended for production):

```yaml
server:
  apiKey: "my-secret-key"
```

## Security Context

The chart supports both pod-level and container-level security contexts:

```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault

containerSecurityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]
```

## Multi-Model Router Mode

Enable `model.multi.enabled` to serve multiple GGUF models from a single deployment using llama-server's built-in router. The chart generates a `--models-preset` INI file from your model definitions and passes `--models-dir` to the server.

Each model runs as a separate child process with independent settings for context size, GPU layer offloading, embedding mode, chat template, and more.

```yaml
model:
  multi:
    enabled: true
    modelsMax: 4
    models:
      - name: bge-embed
        source: hf
        hf:
          repo: "CompendiumLabs/bge-large-en-v1.5-gguf"
          file: "bge-large-en-v1.5-q4_k_m.gguf"
        preload: true
        loadOnStartup: true
        settings:
          embedding: true
          contextSize: 512
          gpuLayers: 0

      - name: qwen-3b
        source: hf
        hf:
          repo: "ggml-org/Qwen2.5-3B-Instruct-GGUF"
          file: "qwen2.5-3b-instruct-q4_k_m.gguf"
        preload: true
        loadOnStartup: true
        settings:
          contextSize: 8192
          gpuLayers: 999
```

Per-model settings available under `settings`:

| Setting        | Description                              |
|---------------|------------------------------------------|
| `contextSize`  | Context window size for this model       |
| `gpuLayers`    | Number of layers to offload to GPU       |
| `embedding`    | Enable embedding mode                    |
| `reranking`    | Enable reranking mode                    |
| `chatTemplate` | Override chat template                   |
| `reasoning`    | Reasoning format (e.g., `deepseek`)      |
| `loadOnStartup`| Load model into memory on server startup |

**Key mapping**: The YAML settings keys use camelCase (e.g., `contextSize`, `gpuLayers`) and are automatically mapped to the CLI-style INI keys (`ctx-size`, `n-gpu-layers`) in the generated ConfigMap. You do not need to use CLI-style names in your values file.

**Limitation**: All models in a multi-model deployment share the same node hardware. To target different hardware profiles (e.g., CPU for embeddings, GPU for chat), use separate Helm releases.

## Example Deployments

The recommended approach for production is to deploy separate Helm releases targeting different hardware profiles.

### embeddings.yaml -- CPU Embedding Server

```yaml
gpu:
  enabled: false
model:
  source: hf
  hf:
    repo: "CompendiumLabs/bge-large-en-v1.5-gguf"
    file: "bge-large-en-v1.5-q4_k_m.gguf"
  preload: true
server:
  embedding: true
  contextSize: 512
  threads: 8
  threadsBatch: 8
  mlock: true
resources:
  requests: { cpu: "8", memory: "4Gi" }
  limits: { cpu: "8", memory: "8Gi" }
```

### small-gpu.yaml -- 1x T4/A10

```yaml
gpu:
  enabled: true
  type: nvidia
  count: 1
model:
  source: hf
  hf:
    repo: "ggml-org/Qwen2.5-3B-Instruct-GGUF"
    file: "qwen2.5-3b-instruct-q4_k_m.gguf"
  preload: true
server:
  contextSize: 8192
  gpuLayers: -1
resources:
  requests: { cpu: "4", memory: "8Gi" }
  limits: { cpu: "4", memory: "16Gi" }
tolerations:
  - key: "nvidia.com/gpu"
    operator: "Exists"
    effect: "NoSchedule"
```

### large-gpu.yaml -- 1x A100/H100

```yaml
gpu:
  enabled: true
  type: nvidia
  count: 1
model:
  source: hf
  hf:
    repo: "ggml-org/Qwen2.5-72B-Instruct-GGUF"
    file: "qwen2.5-72b-instruct-q4_k_m.gguf"
  preload: true
server:
  contextSize: 32768
  gpuLayers: -1
  flashAttention: "on"
resources:
  requests: { cpu: "8", memory: "32Gi" }
  limits: { cpu: "16", memory: "96Gi" }
tolerations:
  - key: "nvidia.com/gpu"
    operator: "Exists"
    effect: "NoSchedule"
```

### Deploy All Three

```bash
helm install embeddings ./charts/llama-cpp-server -f embeddings.yaml
helm install small-gpu  ./charts/llama-cpp-server -f small-gpu.yaml
helm install large-gpu  ./charts/llama-cpp-server -f large-gpu.yaml
```

## Validation

The chart validates required fields at template render time and fails with clear error messages for common misconfigurations:

- `model.hf.repo` is required when `model.source` is `hf` (single-model only)
- `model.hf.file` is required when using preload with HuggingFace source (single-model only)
- `model.s3.bucket` and `model.s3.key` are required when `model.source` is `s3` (single-model only)
- `model.multi.models` must not be empty when `model.multi.enabled` is `true`
- `gpu.count` must be greater than 0 when `gpu.enabled` is `true`
- `gpu.vulkanResource` must be set when `gpu.type` is `vulkan`
- `model.url` is required when `model.source` is `url` (single-model only)
- `model.multi.models[N].hf.file` is required when source is `hf` and `preload` is `true`
- `persistentVolume.accessModes` must include `ReadWriteMany` when `replicaCount > 1` or `autoscaling` is enabled
- `server.apiKey` or `server.apiKeySecret` must be set when `ingress` is enabled
- `persistentVolume.accessModes` must include `ReadWriteMany` when `knative.enabled` is `true` (Knative may auto-scale to multiple replicas)
- `networkPolicy.enabled` and `knative.enabled` cannot both be `true` (Knative manages its own networking)
- `model.multi.models[N].s3.bucket` is required when source is `s3` and `preload` is `true`
- `model.multi.models[N].s3.key` is required when source is `s3` and `preload` is `true`
- `model.multi.models[N].url` is required when source is `url` and `preload` is `true`

## Configuration Reference

### General

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas (ignored when autoscaling.enabled) | `1` |
| `updateStrategy` | Deployment update strategy | `{type: RollingUpdate, ...}` |
| `nameOverride` | Override chart name | `""` |
| `fullnameOverride` | Override full release name | `""` |

### Image

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | Container image repository | `ghcr.io/ggml-org/llama.cpp` |
| `image.tag` | Image tag (auto-computed from `gpu.type` + `appVersion` if empty, e.g. `server-cuda-b4738`) | `""` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `imagePullSecrets` | Image pull secrets | `[]` |

### Init Container

| Parameter | Description | Default |
|-----------|-------------|---------|
| `initContainer.image.repository` | Init container image repository | `alpine` |
| `initContainer.image.tag` | Init container image tag | `"3.20"` |
| `initContainer.resources` | Init container resource requests and limits | `{}` |

### GPU

| Parameter | Description | Default |
|-----------|-------------|---------|
| `gpu.enabled` | Enable GPU support | `false` |
| `gpu.type` | GPU type: `nvidia`, `amd`, `intel`, `vulkan` | `"nvidia"` |
| `gpu.count` | Number of GPUs to request | `1` |
| `gpu.nvidiaResource` | NVIDIA resource key (for MIG, custom plugins) | `"nvidia.com/gpu"` |
| `gpu.amdResource` | AMD resource key | `"amd.com/gpu"` |
| `gpu.intelResource` | Intel resource key | `"gpu.intel.com/i915"` |
| `gpu.vulkanResource` | Vulkan resource key (no standard key; set manually) | `""` |

### Model

| Parameter | Description | Default |
|-----------|-------------|---------|
| `model.path` | Path to GGUF file on the persistent volume | `/models/model.gguf` |
| `model.alias` | Model alias shown in `/v1/models` | `""` |
| `model.source` | Model source: `hf`, `url`, `s3`, or `""` (existing PVC file) | `""` |
| `model.url` | Direct URL to GGUF file (when `source: url`) | `""` |
| `model.hf.repo` | HuggingFace repo ID | `""` |
| `model.hf.file` | Specific file within HF repo (required for preload) | `""` |
| `model.s3.bucket` | S3 bucket name | `""` |
| `model.s3.key` | S3 object key | `""` |
| `model.s3.region` | S3 region | `""` |
| `model.s3.endpoint` | S3-compatible endpoint (e.g., MinIO) | `""` |
| `model.preload` | Download model in init container before server starts | `false` |
| `model.credentials.existingSecret` | Existing secret for download credentials | `""` |
| `model.credentials.secretKeys` | Mapping of env var names to secret keys | `{}` |

### Multi-Model

| Parameter | Description | Default |
|-----------|-------------|---------|
| `model.multi.enabled` | Enable multi-model router mode | `false` |
| `model.multi.modelsDir` | Directory containing GGUF files | `/models` |
| `model.multi.modelsMax` | Maximum models loaded simultaneously | `4` |
| `model.multi.models` | List of model definitions (see Multi-Model section) | `[]` |

### Server

| Parameter | Description | Default |
|-----------|-------------|---------|
| `server.contextSize` | Context window size (0 = model default) | `0` |
| `server.parallel` | Concurrent request slots (empty = auto) | `""` |
| `server.batchSize` | Prompt batch size | `""` |
| `server.ubatchSize` | Micro-batch size | `""` |
| `server.httpThreads` | HTTP worker threads | `""` |
| `server.gpuLayers` | GPU layers to offload (-1 = all) | `-1` |
| `server.splitMode` | Multi-GPU split mode: `none`, `layer`, `row` | `""` |
| `server.tensorSplit` | Per-GPU VRAM distribution (e.g., `"0.5,0.5"`) | `""` |
| `server.mainGpu` | Primary GPU index (only used when splitMode is set) | `0` |
| `server.flashAttention` | Flash Attention: `""` (omit flag — server decides based on model), `"on"`, `"off"`, `"auto"` | `""` |
| `server.threads` | CPU generation threads (empty = auto) | `""` |
| `server.threadsBatch` | CPU batch processing threads (empty = auto) | `""` |
| `server.mlock` | Lock model in RAM (prevent swapping) | `false` |
| `server.metrics` | Enable Prometheus `/metrics` endpoint | `true` |
| `server.embedding` | Embedding-only mode | `false` |
| `server.reranking` | Reranking mode | `false` |
| `server.reasoning` | Reasoning format: `""`, `none`, `deepseek`, `deepseek-legacy`, `auto` | `""` |
| `server.chatTemplate` | Override chat template | `""` |
| `server.apiKey` | API key for authentication (plain text; prefer apiKeySecret) | `""` |
| `server.apiKeySecret` | Existing secret containing API key (key: "api-key") | `""` |
| `server.warmup` | Warm up model on startup | `true` |
| `server.offline` | Prevent all network access | `false` |

### Probes

| Parameter | Description | Default |
|-----------|-------------|---------|
| `startupProbe.enabled` | Enable startup probe | `true` |
| `startupProbe.path` | Startup probe path | `/health` |
| `startupProbe.initialDelaySeconds` | Initial delay | `10` |
| `startupProbe.periodSeconds` | Check interval | `10` |
| `startupProbe.timeoutSeconds` | Timeout | `5` |
| `startupProbe.failureThreshold` | Failures before restart (120 x 10s = 20 min) | `120` |
| `livenessProbe.enabled` | Enable liveness probe | `true` |
| `livenessProbe.path` | Liveness probe path | `/health` |
| `livenessProbe.periodSeconds` | Check interval | `10` |
| `livenessProbe.timeoutSeconds` | Timeout | `5` |
| `livenessProbe.failureThreshold` | Failures before restart | `3` |
| `readinessProbe.enabled` | Enable readiness probe | `true` |
| `readinessProbe.path` | Readiness probe path (503 when no slots free) | `/health?fail_on_no_slot=1` |
| `readinessProbe.periodSeconds` | Check interval | `5` |
| `readinessProbe.timeoutSeconds` | Timeout | `3` |
| `readinessProbe.failureThreshold` | Failures before unready | `3` |

### Autoscaling

| Parameter | Description | Default |
|-----------|-------------|---------|
| `autoscaling.enabled` | Enable HPA | `false` |
| `autoscaling.minReplicas` | Minimum replicas | `1` |
| `autoscaling.maxReplicas` | Maximum replicas | `5` |
| `autoscaling.targetCPUUtilizationPercentage` | Target CPU utilization | `80` |
| `autoscaling.targetMemoryUtilizationPercentage` | Target memory utilization | `""` |

### Pod Disruption Budget

| Parameter | Description | Default |
|-----------|-------------|---------|
| `podDisruptionBudget.enabled` | Enable PodDisruptionBudget (not rendered when Knative is enabled) | `false` |
| `podDisruptionBudget.minAvailable` | Minimum available pods during voluntary disruption | `1` |
| `podDisruptionBudget.maxUnavailable` | Maximum unavailable pods (mutually exclusive with minAvailable) | `""` |

### Knative

| Parameter | Description | Default |
|-----------|-------------|---------|
| `knative.enabled` | Enable Knative Serving (replaces Deployment) | `false` |
| `knative.containerConcurrency` | Max concurrent requests per container (0 = unlimited) | `0` |
| `knative.timeoutSeconds` | Request timeout | `600` |
| `knative.idleTimeoutSeconds` | Idle timeout before scale-to-zero | `600` |
| `knative.autoscalingTarget` | Autoscaling target (default: containerConcurrency) | `""` |
| `knative.progressDeadline` | Deadline for revision to become ready | `"2400s"` |

### Service

| Parameter | Description | Default |
|-----------|-------------|---------|
| `service.type` | Kubernetes Service type | `ClusterIP` |
| `service.port` | Service port | `8080` |
| `service.annotations` | Service annotations | `{}` |

### Ingress

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ingress.enabled` | Enable Ingress | `false` |
| `ingress.className` | Ingress class name | `""` |
| `ingress.annotations` | Ingress annotations | `{}` |
| `ingress.hosts` | Ingress host rules | `[{host: llama.local, paths: [{path: /, pathType: Prefix}]}]` |
| `ingress.tls` | TLS configuration | `[]` |

### Network Policy

Optional NetworkPolicy for restricting pod ingress and egress traffic. Automatically disabled when Knative is enabled (Knative manages its own networking). By default, egress allows DNS (port 53) and HTTPS (port 443).

| Parameter | Description | Default |
|-----------|-------------|---------|
| `networkPolicy.enabled` | Create a NetworkPolicy for the pods | `false` |
| `networkPolicy.ingress.from` | Allowed ingress sources (empty = same namespace only) | `[]` |
| `networkPolicy.egress.extraRules` | Additional egress rules beyond the default DNS and HTTPS | `[]` |

### Monitoring

| Parameter | Description | Default |
|-----------|-------------|---------|
| `serviceMonitor.enabled` | Create Prometheus ServiceMonitor | `false` |
| `serviceMonitor.interval` | Scrape interval | `30s` |
| `serviceMonitor.scrapeTimeout` | Scrape timeout | `10s` |
| `serviceMonitor.labels` | Labels to match Prometheus serviceMonitorSelector | `{}` |

### Persistent Volume

| Parameter | Description | Default |
|-----------|-------------|---------|
| `persistentVolume.enabled` | Create a PVC for model storage | `true` |
| `persistentVolume.size` | PVC size | `30Gi` |
| `persistentVolume.accessModes` | PVC access modes | `["ReadWriteOnce"]` |
| `persistentVolume.storageClass` | Storage class (empty = cluster default) | `""` |
| `persistentVolume.existingClaim` | Use an existing PVC | `""` |
| `persistentVolume.mountPath` | Mount path in container | `/models` |

### Service Account

| Parameter | Description | Default |
|-----------|-------------|---------|
| `serviceAccount.create` | Create a ServiceAccount | `true` |
| `serviceAccount.name` | ServiceAccount name (auto-generated if empty) | `""` |
| `serviceAccount.annotations` | ServiceAccount annotations | `{}` |

### Resources and Scheduling

| Parameter | Description | Default |
|-----------|-------------|---------|
| `resources` | CPU/memory resource requests and limits | `{}` |
| `podAnnotations` | Additional pod annotations (e.g., Prometheus scrape, Istio sidecar) | `{}` |
| `podLabels` | Additional pod labels | `{}` |
| `runtimeClassName` | Runtime class name (e.g., "nvidia" for GPU runtime) | `""` |
| `terminationGracePeriodSeconds` | Termination grace period in seconds | `90` |
| `podSecurityContext` | Pod-level security context | See values.yaml |
| `containerSecurityContext` | Container-level security context | See values.yaml |
| `nodeSelector` | Node selector labels | `{}` |
| `tolerations` | Pod tolerations | `[]` |
| `affinity` | Pod affinity rules | `{}` |

**Resource quota note**: The default `resources: {}` sets no requests or limits. In namespaces with `ResourceQuota` enforcement, you **must** set `resources.requests` and `resources.limits` or pods will be rejected by the admission controller. Example:

```yaml
resources:
  requests:
    cpu: "4"
    memory: "8Gi"
  limits:
    cpu: "8"
    memory: "16Gi"
```

**LimitRange note**: If your namespace has a `LimitRange`, ensure your resource values are within its min/max bounds. LimitRange defaults may also apply to the init container — set `initContainer.resources` explicitly to avoid unexpected resource allocation during model downloads.

### Escape Hatches

| Parameter | Description | Default |
|-----------|-------------|---------|
| `extraEnv` | Additional environment variables | `[]` |
| `extraEnvFrom` | Additional environment variable sources | `[]` |
| `extraVolumes` | Additional volumes | `[]` |
| `extraVolumeMounts` | Additional volume mounts | `[]` |
| `extraArgs` | Additional CLI arguments appended to server command | `[]` |

## Monitoring

llama-server exposes a Prometheus-compatible `/metrics` endpoint, enabled by default via `server.metrics: true`.

To integrate with the Prometheus Operator, enable the ServiceMonitor:

```yaml
serviceMonitor:
  enabled: true
  interval: 30s
  labels:
    release: prometheus   # match your Prometheus serviceMonitorSelector
```

The metrics endpoint runs on the same port as the API (default `8080`).

## Knative

When `knative.enabled: true`, the chart renders a Knative Service instead of a Deployment. This enables serverless scale-to-zero behavior, which is useful for infrequently-used models.

```yaml
knative:
  enabled: true
  containerConcurrency: 4
  timeoutSeconds: 600
  idleTimeoutSeconds: 600
  progressDeadline: "2400s"
```

The `progressDeadline` is set to 2400s (40 minutes) by default. This is intentionally high to accommodate ASG cold starts in cloud environments, where provisioning a new GPU node can take 20-40 minutes. If your cluster has pre-provisioned GPU nodes, you can reduce this value.

When Knative is enabled, the standard Deployment and HPA resources are not created.

**Required feature flags**: Knative Serving must have the following feature flags enabled for full compatibility with this chart:
- `kubernetes.podspec-persistent-volume-claim` -- required for PVC model storage
- `kubernetes.podspec-init-containers` -- required for model preloading

See the [Knative feature flags documentation](https://knative.dev/docs/serving/configuration/feature-flags/) for configuration details.
