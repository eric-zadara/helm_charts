{{/*
Expand the name of the chart.
*/}}
{{- define "onyx-ai.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "onyx-ai.fullname" -}}
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
{{- define "onyx-ai.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "onyx-ai.labels" -}}
helm.sh/chart: {{ include "onyx-ai.chart" . }}
{{ include "onyx-ai.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "onyx-ai.selectorLabels" -}}
app.kubernetes.io/name: {{ include "onyx-ai.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "onyx-ai.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "onyx-ai.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Validate the global variant setting.
Fails with clear error message if invalid.
Usage: {{ include "onyx-ai.validateVariant" . }}
*/}}
{{- define "onyx-ai.validateVariant" -}}
{{- $variant := .Values.global.variant | default "onyx" -}}
{{- $validVariants := list "onyx" "onyx-foss" "custom" -}}
{{- if not (has $variant $validVariants) -}}
{{- fail (printf "Invalid variant '%s'. Valid options: onyx, onyx-foss, custom" $variant) -}}
{{- end -}}
{{- end -}}

{{/*
Get the image repository for a component based on variant.
Args (passed as dict):
  - ctx: the root context (.)
  - component: one of "backend", "web-server", "model-server", "code-interpreter"
  - override: optional explicit repository override (takes precedence)
Returns: fully qualified image repository (with registry prefix if set)

Usage: {{ include "onyx-ai.imageRepository" (dict "ctx" . "component" "backend") }}
*/}}
{{- define "onyx-ai.imageRepository" -}}
{{- $variant := .ctx.Values.global.variant | default "onyx" -}}
{{- $registry := .ctx.Values.global.imageRegistry | default "" -}}
{{- $override := .override | default "" -}}
{{- /* Return override if provided */ -}}
{{- if $override -}}
  {{- if $registry -}}
    {{- printf "%s/%s" $registry $override -}}
  {{- else -}}
    {{- $override -}}
  {{- end -}}
{{- else -}}
  {{- /* Lookup from variant mapping */ -}}
  {{- $repos := dict
      "backend" (dict "onyx" "onyxdotapp/onyx-backend" "onyx-foss" "onyxdotapp/onyx-backend" "custom" "")
      "web-server" (dict "onyx" "onyxdotapp/onyx-web-server" "onyx-foss" "onyxdotapp/onyx-web-server" "custom" "")
      "model-server" (dict "onyx" "onyxdotapp/onyx-model-server" "onyx-foss" "onyxdotapp/onyx-model-server" "custom" "")
      "code-interpreter" (dict "onyx" "onyxdotapp/code-interpreter" "onyx-foss" "onyxdotapp/code-interpreter" "custom" "")
  -}}
  {{- $componentRepos := index $repos .component -}}
  {{- $repo := index $componentRepos $variant -}}
  {{- /* Custom variant with no repo = error */ -}}
  {{- if and (eq $variant "custom") (not $repo) -}}
    {{- fail (printf "Custom variant requires explicit image repository for component '%s'. Set onyx.<component>.image.repository in values." .component) -}}
  {{- end -}}
  {{- /* Apply registry prefix if set */ -}}
  {{- if and $registry $repo -}}
    {{- printf "%s/%s" $registry $repo -}}
  {{- else -}}
    {{- $repo -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
================================================================================
PostgreSQL Helper Functions (Phase 3)
================================================================================
*/}}

{{/*
Get PostgreSQL host based on configuration.
Returns pooler service when pooler is enabled, direct PostgreSQL service otherwise,
or external host when CNPG is disabled.

cnpg/cluster chart naming convention:
  - Cluster name: {release}-postgresql-cluster (from alias)
  - RW service: {release}-postgresql-cluster-rw
  - Pooler service: {release}-postgresql-cluster-rw (pooler named "rw")

Usage: {{ include "onyx-ai.postgresql.host" . }}
*/}}
{{- define "onyx-ai.postgresql.host" -}}
{{- if not .Values.cnpg.enabled -}}
  {{- /* External PostgreSQL mode */ -}}
  {{- required "externalPostgresql.host is required when cnpg.enabled is false" .Values.externalPostgresql.host -}}
{{- else if .Values.cnpg.pooler.enabled -}}
  {{- /* CNPG with PgBouncer pooler - pooler named "rw" creates same service name */ -}}
  {{- printf "%s-postgresql-cluster-rw" .Release.Name -}}
{{- else -}}
  {{- /* CNPG direct connection (no pooler) */ -}}
  {{- printf "%s-postgresql-cluster-rw" .Release.Name -}}
{{- end -}}
{{- end -}}

{{/*
Get PostgreSQL port.
Returns 5432 for CNPG (both pooler and direct), or external port when configured.

Usage: {{ include "onyx-ai.postgresql.port" . }}
*/}}
{{- define "onyx-ai.postgresql.port" -}}
{{- if not .Values.cnpg.enabled -}}
  {{- .Values.externalPostgresql.port | default 5432 -}}
{{- else -}}
  {{- /* CNPG always uses 5432 */ -}}
  {{- 5432 -}}
{{- end -}}
{{- end -}}

{{/*
Get PostgreSQL app secret name (for application connections).
CNPG generates: {cluster-name}-app with username, password, host, port, dbname, uri keys.
For external: use existingSecret or wrapper-generated secret.

cnpg/cluster chart naming: {release}-postgresql-cluster-app

Usage: {{ include "onyx-ai.postgresql.secretName" . }}
*/}}
{{- define "onyx-ai.postgresql.secretName" -}}
{{- if not .Values.cnpg.enabled -}}
  {{- if .Values.externalPostgresql.existingSecret -}}
    {{- .Values.externalPostgresql.existingSecret -}}
  {{- else -}}
    {{- printf "%s-external-postgresql" (include "onyx-ai.fullname" .) -}}
  {{- end -}}
{{- else -}}
  {{- /* CNPG app secret follows convention: {cluster-name}-app */ -}}
  {{- printf "%s-postgresql-cluster-app" .Release.Name -}}
{{- end -}}
{{- end -}}

{{/*
Get PostgreSQL superuser secret name (for migrations/admin).
Only applicable for CNPG mode.

cnpg/cluster chart naming: {release}-postgresql-cluster-superuser

Usage: {{ include "onyx-ai.postgresql.superuserSecretName" . }}
*/}}
{{- define "onyx-ai.postgresql.superuserSecretName" -}}
{{- if .Values.cnpg.enabled -}}
  {{- /* CNPG superuser secret follows convention: {cluster-name}-superuser */ -}}
  {{- printf "%s-postgresql-cluster-superuser" .Release.Name -}}
{{- end -}}
{{- end -}}

{{/*
Get PostgreSQL database name.
CNPG default database is 'app'. External uses configured value.

Usage: {{ include "onyx-ai.postgresql.database" . }}
*/}}
{{- define "onyx-ai.postgresql.database" -}}
{{- if not .Values.cnpg.enabled -}}
  {{- .Values.externalPostgresql.database | default "postgres" -}}
{{- else -}}
  {{- /* CNPG default database is 'app' */ -}}
  {{- "app" -}}
{{- end -}}
{{- end -}}

{{/*
Validate PostgreSQL configuration.
Fails if cnpg is disabled but external PostgreSQL is not properly configured.

Usage: {{ include "onyx-ai.postgresql.validate" . }}
*/}}
{{- define "onyx-ai.postgresql.validate" -}}
{{- if not .Values.cnpg.enabled -}}
  {{- if not .Values.externalPostgresql.host -}}
    {{- fail "externalPostgresql.host is required when cnpg.enabled is false" -}}
  {{- end -}}
  {{- if and (not .Values.externalPostgresql.existingSecret) (not .Values.externalPostgresql.username) -}}
    {{- fail "externalPostgresql.existingSecret or externalPostgresql.username is required when cnpg.enabled is false" -}}
  {{- end -}}
{{- end -}}
{{- end -}}
