{{/*
Expand the name of the chart.
*/}}
{{- define "networking-layer.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "networking-layer.fullname" -}}
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
{{- define "networking-layer.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "networking-layer.labels" -}}
helm.sh/chart: {{ include "networking-layer.chart" . }}
{{ include "networking-layer.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "networking-layer.selectorLabels" -}}
app.kubernetes.io/name: {{ include "networking-layer.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Return the GatewayClass name.
Uses gatewayClass.name if provided, otherwise defaults to "llm-gateway".
*/}}
{{- define "networking-layer.gatewayClassName" -}}
{{- .Values.gatewayClass.name | default "llm-gateway" }}
{{- end }}

{{/*
Return the Gateway name.
Uses gateway.name if provided, otherwise uses fullname.
*/}}
{{- define "networking-layer.gatewayName" -}}
{{- .Values.gateway.name | default (include "networking-layer.fullname" .) }}
{{- end }}
