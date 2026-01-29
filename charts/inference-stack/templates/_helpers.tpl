{{/*
Expand the name of the chart.
*/}}
{{- define "inference-stack.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "inference-stack.fullname" -}}
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
{{- define "inference-stack.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "inference-stack.labels" -}}
helm.sh/chart: {{ include "inference-stack.chart" . }}
{{ include "inference-stack.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "inference-stack.selectorLabels" -}}
app.kubernetes.io/name: {{ include "inference-stack.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Get the infrastructure namespace.
Defaults to release namespace if not specified.
*/}}
{{- define "inference-stack.infrastructureNamespace" -}}
{{- if .Values.infrastructureNamespace }}
{{- .Values.infrastructureNamespace }}
{{- else }}
{{- .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
Compute the LiteLLM proxy service name based on infrastructure release name.
Convention: <infrastructureReleaseName>-litellm-proxy
*/}}
{{- define "inference-stack.litellmService" -}}
{{- printf "%s-litellm-proxy" .Values.infrastructureReleaseName }}
{{- end }}

{{/*
Compute the LiteLLM proxy FQDN.
Convention: <infrastructureReleaseName>-litellm-proxy.<namespace>.svc.cluster.local
*/}}
{{- define "inference-stack.litellmServiceFQDN" -}}
{{- printf "%s-litellm-proxy.%s.svc.cluster.local" .Values.infrastructureReleaseName (include "inference-stack.infrastructureNamespace" .) }}
{{- end }}

{{/*
Compute the networking layer gateway name based on infrastructure release name.
Convention: <infrastructureReleaseName>-networking-layer-gateway
*/}}
{{- define "inference-stack.gatewayName" -}}
{{- printf "%s-networking-layer-gateway" .Values.infrastructureReleaseName }}
{{- end }}

{{/*
Compute the internal inference gateway name for this release.
Convention: <release>-inference-gateway
*/}}
{{- define "inference-stack.inferenceGatewayName" -}}
{{- printf "%s-inference-gateway" .Release.Name }}
{{- end }}

{{/*
Compute the EPP service name for this release.
Convention: <release>-inference-gateway-epp
*/}}
{{- define "inference-stack.eppServiceName" -}}
{{- printf "%s-inference-gateway-epp" .Release.Name }}
{{- end }}
