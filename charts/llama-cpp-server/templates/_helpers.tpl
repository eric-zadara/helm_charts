{{/*
Expand the name of the chart.
*/}}
{{- define "llama-cpp-server.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "llama-cpp-server.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "llama-cpp-server.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "llama-cpp-server.labels" -}}
helm.sh/chart: {{ include "llama-cpp-server.chart" . }}
{{ include "llama-cpp-server.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "llama-cpp-server.selectorLabels" -}}
app.kubernetes.io/name: {{ include "llama-cpp-server.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use.
*/}}
{{- define "llama-cpp-server.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "llama-cpp-server.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Determine the image tag.
If .Values.image.tag is set, use it directly.
If gpu.enabled, build "server-{suffix}" based on gpu.type mapping:
  nvidia -> cuda, amd -> rocm, intel -> intel, vulkan -> vulkan.
Otherwise return "server" (CPU-only).
When appVersion is set and not "0.0.0", append it for version pinning
(e.g. "server-cuda-b4738"). Fall back to the unpinned tag otherwise.
Note: ROCm (amd) images are only published as "server-rocm" without a
build-number suffix, so appVersion is never appended for gpu.type=amd.
*/}}
{{- define "llama-cpp-server.imageTag" -}}
{{- if .Values.image.tag }}
{{- .Values.image.tag }}
{{- else }}
{{- $base := "server" }}
{{- $skipVersion := false }}
{{- if .Values.gpu.enabled }}
{{- $suffixMap := dict "nvidia" "cuda" "amd" "rocm" "intel" "intel" "vulkan" "vulkan" }}
{{- $suffix := get $suffixMap .Values.gpu.type }}
{{- $base = printf "server-%s" $suffix }}
{{- if eq .Values.gpu.type "amd" }}
{{- $skipVersion = true }}
{{- end }}
{{- end }}
{{- if and (not $skipVersion) .Chart.AppVersion (ne .Chart.AppVersion "0.0.0") }}
{{- printf "%s-%s" $base .Chart.AppVersion }}
{{- else }}
{{- $base }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Return the GPU resource key based on gpu.type.
nvidia -> nvidiaResource value, amd -> amdResource value, intel -> intelResource value.
Vulkan has no standard Kubernetes device-plugin resource key; scheduling for Vulkan GPUs
requires manual configuration (nodeSelector, tolerations, or a custom device plugin).
Set gpu.vulkanResource if your cluster exposes a Vulkan device resource.
*/}}
{{- define "llama-cpp-server.gpuResourceKey" -}}
{{- if eq .Values.gpu.type "nvidia" }}
{{- .Values.gpu.nvidiaResource }}
{{- else if eq .Values.gpu.type "amd" }}
{{- .Values.gpu.amdResource }}
{{- else if eq .Values.gpu.type "intel" }}
{{- .Values.gpu.intelResource }}
{{- else if eq .Values.gpu.type "vulkan" }}
{{- .Values.gpu.vulkanResource }}
{{- else }}
{{- print "" }}
{{- end }}
{{- end }}
