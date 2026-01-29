{{/*
Expand the name of the chart.
*/}}
{{- define "model-serving.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "model-serving.fullname" -}}
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
{{- define "model-serving.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "model-serving.labels" -}}
helm.sh/chart: {{ include "model-serving.chart" . }}
{{ include "model-serving.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "model-serving.selectorLabels" -}}
app.kubernetes.io/name: {{ include "model-serving.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Return the ServingRuntime name.
Uses servingRuntime.name if provided, otherwise defaults to "kserve-vllm".
*/}}
{{- define "model-serving.servingRuntimeName" -}}
{{- .Values.servingRuntime.name | default "kserve-vllm" }}
{{- end }}

{{/*
Return the llama.cpp ServingRuntime name.
Uses llamacppRuntime.name if provided, otherwise defaults to "kserve-llamacpp".
*/}}
{{- define "model-serving.llamacppRuntimeName" -}}
{{- .Values.llamacppRuntime.name | default "kserve-llamacpp" }}
{{- end }}

{{/*
Return the Ollama ServingRuntime name.
Uses ollamaRuntime.name if provided, otherwise defaults to "kserve-ollama".
*/}}
{{- define "model-serving.ollamaRuntimeName" -}}
{{- .Values.ollamaRuntime.name | default "kserve-ollama" }}
{{- end }}
