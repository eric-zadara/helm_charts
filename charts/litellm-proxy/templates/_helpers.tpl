{{/*
Expand the name of the chart.
*/}}
{{- define "litellm-proxy.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "litellm-proxy.fullname" -}}
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
{{- define "litellm-proxy.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "litellm-proxy.labels" -}}
helm.sh/chart: {{ include "litellm-proxy.chart" . }}
{{ include "litellm-proxy.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "litellm-proxy.selectorLabels" -}}
app.kubernetes.io/name: {{ include "litellm-proxy.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Return the master key secret name.
Uses existingSecret if set, otherwise the generated secret name.
*/}}
{{- define "litellm-proxy.masterKeySecretName" -}}
{{- if .Values.masterKey.existingSecret }}
{{- .Values.masterKey.existingSecret }}
{{- else }}
{{- printf "%s-master-key" (include "litellm-proxy.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Return the salt key secret name.
Uses existingSecret if set, otherwise the generated secret name.
*/}}
{{- define "litellm-proxy.saltKeySecretName" -}}
{{- if .Values.saltKey.existingSecret }}
{{- .Values.saltKey.existingSecret }}
{{- else }}
{{- printf "%s-salt-key" (include "litellm-proxy.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Return the database password secret name.
Uses passwordSecretName if set, otherwise the generated secret name when create is true.
*/}}
{{- define "litellm-proxy.databaseSecretName" -}}
{{- if .Values.database.password.create }}
{{- printf "%s-db-password" (include "litellm-proxy.fullname" .) }}
{{- else }}
{{- .Values.database.passwordSecretName }}
{{- end }}
{{- end }}

{{/*
Return the cache password secret name.
Uses passwordSecretName if set, otherwise the generated secret name when create is true.
*/}}
{{- define "litellm-proxy.cacheSecretName" -}}
{{- if .Values.cache.password.create }}
{{- printf "%s-cache-password" (include "litellm-proxy.fullname" .) }}
{{- else }}
{{- .Values.cache.passwordSecretName }}
{{- end }}
{{- end }}
