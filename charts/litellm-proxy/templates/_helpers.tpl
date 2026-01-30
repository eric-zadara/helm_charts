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
=============================================================================
DATABASE HELPERS
=============================================================================
*/}}

{{/*
Return the database host.
When internal is enabled, uses the CNPG pooler service name.
Otherwise uses the external host.
*/}}
{{- define "litellm-proxy.databaseHost" -}}
{{- if .Values.database.internal.enabled }}
{{- if .Values.database.internal.pooler.enabled }}
{{- printf "%s-postgresql-pooler-rw" .Release.Name }}
{{- else }}
{{- printf "%s-postgresql-rw" .Release.Name }}
{{- end }}
{{- else }}
{{- .Values.database.external.host }}
{{- end }}
{{- end }}

{{/*
Return the database port.
*/}}
{{- define "litellm-proxy.databasePort" -}}
{{- if .Values.database.internal.enabled }}
{{- 5432 }}
{{- else }}
{{- .Values.database.external.port }}
{{- end }}
{{- end }}

{{/*
Return the database name.
*/}}
{{- define "litellm-proxy.databaseName" -}}
{{- if .Values.database.internal.enabled }}
{{- .Values.database.internal.database }}
{{- else }}
{{- .Values.database.external.name }}
{{- end }}
{{- end }}

{{/*
Return the database user.
*/}}
{{- define "litellm-proxy.databaseUser" -}}
{{- if .Values.database.internal.enabled }}
{{- .Values.database.internal.owner }}
{{- else }}
{{- .Values.database.external.user }}
{{- end }}
{{- end }}

{{/*
Return the database password secret name.
When internal is enabled, uses CNPG convention: {release}-postgresql-app
Otherwise uses the external secret name.
*/}}
{{- define "litellm-proxy.databaseSecretName" -}}
{{- if .Values.database.internal.enabled }}
{{- printf "%s-postgresql-app" .Release.Name }}
{{- else }}
{{- .Values.database.external.secretName }}
{{- end }}
{{- end }}

{{/*
Return the database password secret key.
*/}}
{{- define "litellm-proxy.databaseSecretKey" -}}
{{- if .Values.database.internal.enabled }}
{{- "password" }}
{{- else }}
{{- .Values.database.external.passwordSecretKey }}
{{- end }}
{{- end }}

{{/*
=============================================================================
CACHE HELPERS
=============================================================================
*/}}

{{/*
Return the cache host.
When internal is enabled, uses the Valkey service name.
Otherwise uses the external host (or sentinel host if sentinel enabled).
*/}}
{{- define "litellm-proxy.cacheHost" -}}
{{- if .Values.cache.internal.enabled }}
{{- printf "%s-valkey-master" .Release.Name }}
{{- else if .Values.cache.external.sentinel.enabled }}
{{- .Values.cache.external.host }}
{{- else }}
{{- .Values.cache.external.host }}
{{- end }}
{{- end }}

{{/*
Return the cache port.
*/}}
{{- define "litellm-proxy.cachePort" -}}
{{- if .Values.cache.internal.enabled }}
{{- 6379 }}
{{- else if .Values.cache.external.sentinel.enabled }}
{{- .Values.cache.external.sentinel.port }}
{{- else }}
{{- .Values.cache.external.port }}
{{- end }}
{{- end }}

{{/*
Return whether sentinel mode is enabled.
Internal Valkey uses master/replica mode, not sentinel.
*/}}
{{- define "litellm-proxy.cacheSentinelEnabled" -}}
{{- if .Values.cache.internal.enabled }}
{{- false }}
{{- else }}
{{- .Values.cache.external.sentinel.enabled }}
{{- end }}
{{- end }}

{{/*
Return the cache password secret name.
When internal is enabled, uses Bitnami Valkey convention.
Otherwise uses the external secret name.
*/}}
{{- define "litellm-proxy.cacheSecretName" -}}
{{- if .Values.cache.internal.enabled }}
{{- printf "%s-valkey" .Release.Name }}
{{- else }}
{{- .Values.cache.external.secretName }}
{{- end }}
{{- end }}

{{/*
Return the cache password secret key.
*/}}
{{- define "litellm-proxy.cacheSecretKey" -}}
{{- if .Values.cache.internal.enabled }}
{{- "valkey-password" }}
{{- else }}
{{- .Values.cache.external.passwordSecretKey }}
{{- end }}
{{- end }}

{{/*
=============================================================================
RANDOM KEY GENERATION
=============================================================================
*/}}

{{/*
Generate a random master key if not provided.
Format: sk-<random-32-char-string>
*/}}
{{- define "litellm-proxy.generateMasterKey" -}}
{{- if .Values.masterKey.value }}
{{- .Values.masterKey.value }}
{{- else }}
{{- printf "sk-%s" (randAlphaNum 32) }}
{{- end }}
{{- end }}

{{/*
Generate a random salt key if not provided.
*/}}
{{- define "litellm-proxy.generateSaltKey" -}}
{{- if .Values.saltKey.value }}
{{- .Values.saltKey.value }}
{{- else }}
{{- randAlphaNum 32 }}
{{- end }}
{{- end }}
