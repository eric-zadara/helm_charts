{{/*
Validation guards — included at the top of podSpec to catch misconfiguration early.
*/}}
{{- define "llama-cpp-server.validation" -}}
{{- if and (eq .Values.model.source "hf") (not .Values.model.hf.repo) (not .Values.model.multi.enabled) }}
  {{- fail "model.hf.repo is required when model.source is 'hf'" }}
{{- end }}
{{- if and (eq .Values.model.source "s3") (not .Values.model.s3.bucket) (not .Values.model.multi.enabled) }}
  {{- fail "model.s3.bucket is required when model.source is 's3'" }}
{{- end }}
{{- if and (eq .Values.model.source "s3") (not .Values.model.s3.key) (not .Values.model.multi.enabled) }}
  {{- fail "model.s3.key is required when model.source is 's3'" }}
{{- end }}
{{- if and .Values.model.multi.enabled (not .Values.model.multi.models) }}
  {{- fail "model.multi.models must not be empty when model.multi.enabled is true" }}
{{- end }}
{{- if and .Values.gpu.enabled (le (int .Values.gpu.count) 0) }}
  {{- fail "gpu.count must be > 0 when gpu.enabled is true" }}
{{- end }}
{{- if and .Values.model.preload (eq .Values.model.source "hf") (not .Values.model.hf.file) (not .Values.model.multi.enabled) }}
  {{- fail "model.hf.file is required when using preload with HuggingFace source" }}
{{- end }}
{{/* I5: RWO PVC + multiple replicas validation */}}
{{- $multiReplica := or (gt (int .Values.replicaCount) 1) .Values.autoscaling.enabled }}
{{- if and $multiReplica .Values.persistentVolume.enabled (not .Values.persistentVolume.existingClaim) }}
  {{- $hasRWX := false }}
  {{- range .Values.persistentVolume.accessModes }}
    {{- if eq . "ReadWriteMany" }}
      {{- $hasRWX = true }}
    {{- end }}
  {{- end }}
  {{- if not $hasRWX }}
    {{- fail "persistentVolume.accessModes must include ReadWriteMany (or use existingClaim) when replicaCount > 1 or autoscaling is enabled. Alternatively, use strategy.type: Recreate with node affinity." }}
  {{- end }}
{{- end }}
{{/* Knative + PVC without RWX validation */}}
{{- if and .Values.knative.enabled .Values.persistentVolume.enabled (not .Values.persistentVolume.existingClaim) }}
  {{- $hasRWX := false }}
  {{- range .Values.persistentVolume.accessModes }}
    {{- if eq . "ReadWriteMany" }}
      {{- $hasRWX = true }}
    {{- end }}
  {{- end }}
  {{- if not $hasRWX }}
    {{- fail "persistentVolume.accessModes must include ReadWriteMany (or use existingClaim) when knative.enabled is true, because Knative may scale to multiple replicas that each need to mount the volume." }}
  {{- end }}
{{- end }}
{{/* NetworkPolicy + Knative incompatibility */}}
{{- if and .Values.networkPolicy.enabled .Values.knative.enabled }}
  {{- fail "networkPolicy.enabled and knative.enabled cannot both be true. Knative manages its own networking via Istio/Kourier; use Knative network policies instead." }}
{{- end }}
{{/* I6: Missing model.url validation */}}
{{- if and (eq .Values.model.source "url") (not .Values.model.url) (not .Values.model.multi.enabled) }}
  {{- fail "model.url is required when model.source is 'url'" }}
{{- end }}
{{/* I8: Multi-model HF file validation */}}
{{- if .Values.model.multi.enabled }}
  {{- range $i, $m := .Values.model.multi.models }}
    {{- if and (eq (default "" $m.source) "hf") $m.preload }}
      {{- if not (and $m.hf $m.hf.file) }}
        {{- fail (printf "model.multi.models[%d].hf.file is required when source is 'hf' and preload is true (exact filename needed for download URL)" $i) }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}
{{/* Multi-model S3 preload validation */}}
{{- if .Values.model.multi.enabled }}
  {{- range $i, $m := .Values.model.multi.models }}
    {{- if and (eq (default "" $m.source) "s3") $m.preload }}
      {{- if not (and $m.s3 $m.s3.bucket) }}
        {{- fail (printf "model.multi.models[%d].s3.bucket is required when source is 's3' and preload is true" $i) }}
      {{- end }}
      {{- if not (and $m.s3 $m.s3.key) }}
        {{- fail (printf "model.multi.models[%d].s3.key is required when source is 's3' and preload is true" $i) }}
      {{- end }}
    {{- end }}
    {{- if and (eq (default "" $m.source) "url") $m.preload }}
      {{- if not $m.url }}
        {{- fail (printf "model.multi.models[%d].url is required when source is 'url' and preload is true" $i) }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}
{{/* N4: Vulkan GPU requires vulkanResource to be set */}}
{{- if and .Values.gpu.enabled (eq .Values.gpu.type "vulkan") (not .Values.gpu.vulkanResource) }}
  {{- fail "gpu.vulkanResource must be set when gpu.type is 'vulkan' (no standard Kubernetes device-plugin resource key exists for Vulkan)" }}
{{- end }}
{{/* I13: Ingress without authentication validation */}}
{{- if and .Values.ingress.enabled (not .Values.server.apiKey) (not .Values.server.apiKeySecret) }}
  {{- fail "server.apiKey or server.apiKeySecret must be set when ingress is enabled (server would be exposed without authentication)" }}
{{- end }}
{{/* TLS is intentionally not validated here — many production setups terminate TLS at the
     load balancer or ingress controller, so requiring ingress.tls would break valid configs.
     Users exposing Ingress should ensure TLS is terminated somewhere in the request path. */}}
{{- end }}
