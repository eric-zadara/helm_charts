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

{{/*
================================================================================
Redis Helper Functions (Phase 4)
================================================================================
*/}}

{{/*
Get Redis host based on configuration mode.
Priority: External > HA > Default OT Redis

For each mode:
- External: Uses externalRedis.host directly
- HA (Spotahome): Uses rfs-{release}-redis-ha (Sentinel service publishes master)
- Default (OT Redis): Uses {release}-master

Note: Onyx does NOT use Sentinel protocol natively - it uses direct redis:// URLs.
For HA mode, we connect to the Sentinel-managed Redis service, not the Sentinel protocol.

Usage: {{ include "onyx-ai.redis.host" . }}
*/}}
{{- define "onyx-ai.redis.host" -}}
{{- if .Values.externalRedis.host -}}
  {{- /* External Redis mode */ -}}
  {{- .Values.externalRedis.host -}}
{{- else if .Values.redis.ha.enabled -}}
  {{- /* Spotahome Redis HA mode - rfr service for Redis pods */ -}}
  {{- /* Note: rfs-{name} is Sentinel, rfr-{name} is Redis */ -}}
  {{- /* Onyx needs direct Redis connection, not Sentinel protocol */ -}}
  {{- printf "rfr-%s-redis-ha" .Release.Name -}}
{{- else -}}
  {{- /* Default OT Container Kit Redis: {release}-master */ -}}
  {{- printf "%s-master" .Release.Name -}}
{{- end -}}
{{- end -}}

{{/*
Get Redis port.
External Redis can configure custom port, all others use 6379.

Usage: {{ include "onyx-ai.redis.port" . }}
*/}}
{{- define "onyx-ai.redis.port" -}}
{{- if .Values.externalRedis.host -}}
  {{- .Values.externalRedis.port | default 6379 -}}
{{- else -}}
  {{- /* Both OT Redis and Spotahome HA use 6379 */ -}}
  {{- 6379 -}}
{{- end -}}
{{- end -}}

{{/*
Get Redis secret name based on configuration mode.
- External: externalRedis.existingSecret or wrapper-generated secret
- HA: Wrapper-generated secret (onyx-ai-redis-ha)
- Default: onyx-redis (upstream OT Redis secret from auth.redis)

Usage: {{ include "onyx-ai.redis.secretName" . }}
*/}}
{{- define "onyx-ai.redis.secretName" -}}
{{- if .Values.externalRedis.host -}}
  {{- if .Values.externalRedis.existingSecret -}}
    {{- .Values.externalRedis.existingSecret -}}
  {{- else -}}
    {{- printf "%s-external-redis" (include "onyx-ai.fullname" .) -}}
  {{- end -}}
{{- else if .Values.redis.ha.enabled -}}
  {{- /* Spotahome HA mode - we create a secret for Redis password */ -}}
  {{- printf "%s-redis-ha" (include "onyx-ai.fullname" .) -}}
{{- else -}}
  {{- /* OT Redis uses secret name from upstream auth.redis */ -}}
  {{- "onyx-redis" -}}
{{- end -}}
{{- end -}}

{{/*
Get Redis secret key name.
The key name within the secret that contains the password.
- OT Redis and External: redis_password (matches upstream pattern)
- HA: redis_password (for consistency)

Usage: {{ include "onyx-ai.redis.secretKey" . }}
*/}}
{{- define "onyx-ai.redis.secretKey" -}}
{{- "redis_password" -}}
{{- end -}}

{{/*
Get Redis database number.
Used for REDIS_DB_NUMBER environment variable.

Usage: {{ include "onyx-ai.redis.database" . }}
*/}}
{{- define "onyx-ai.redis.database" -}}
{{- if .Values.externalRedis.host -}}
  {{- .Values.externalRedis.database | default 0 -}}
{{- else -}}
  {{- .Values.redis.database | default 0 -}}
{{- end -}}
{{- end -}}

{{/*
Check if Redis TLS should be enabled.
Only applicable for external Redis connections.

Usage: {{ include "onyx-ai.redis.tlsEnabled" . }}
*/}}
{{- define "onyx-ai.redis.tlsEnabled" -}}
{{- if and .Values.externalRedis.host .Values.externalRedis.tls.enabled -}}
  {{- "true" -}}
{{- else -}}
  {{- "false" -}}
{{- end -}}
{{- end -}}

{{/*
Validate Redis configuration.
Fails if multiple exclusive modes are enabled or required fields are missing.

Usage: {{ include "onyx-ai.redis.validate" . }}
*/}}
{{- define "onyx-ai.redis.validate" -}}
{{- $modes := 0 -}}
{{- $modeNames := list -}}
{{- /* Count active modes - check each independently */ -}}
{{- if .Values.redis.enabled -}}
  {{- $modes = add $modes 1 -}}
  {{- $modeNames = append $modeNames "redis.enabled (OT Redis)" -}}
{{- end -}}
{{- if .Values.redis.ha.enabled -}}
  {{- $modes = add $modes 1 -}}
  {{- $modeNames = append $modeNames "redis.ha.enabled (Spotahome HA)" -}}
{{- end -}}
{{- if .Values.externalRedis.host -}}
  {{- $modes = add $modes 1 -}}
  {{- $modeNames = append $modeNames "externalRedis.host (External)" -}}
{{- end -}}
{{- /* Validate exactly one mode is active */ -}}
{{- if eq $modes 0 -}}
  {{- fail "No Redis mode is active. Enable one of: redis.enabled, redis.ha.enabled, or set externalRedis.host" -}}
{{- end -}}
{{- if gt $modes 1 -}}
  {{- fail (printf "Multiple Redis modes active: %s. Only one mode can be active at a time." (join ", " $modeNames)) -}}
{{- end -}}
{{- /* Validate external Redis has credentials */ -}}
{{- if .Values.externalRedis.host -}}
  {{- if and (not .Values.externalRedis.existingSecret) (not .Values.externalRedis.password) -}}
    {{- fail "externalRedis.existingSecret or externalRedis.password is required when externalRedis.host is set" -}}
  {{- end -}}
{{- end -}}
{{- /* Validate HA mode has minimum sentinels for quorum */ -}}
{{- if .Values.redis.ha.enabled -}}
  {{- $sentinels := .Values.redis.ha.sentinels | default 3 -}}
  {{- if lt (int $sentinels) 3 -}}
    {{- fail "redis.ha.sentinels must be at least 3 for Sentinel quorum" -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
================================================================================
Object Storage Helper Functions (Phase 5)
================================================================================
*/}}

{{/*
Get S3 endpoint URL.
Returns empty string for AWS S3 (boto3 uses default), or configured endpoint for self-hosted.

Usage: {{ include "onyx-ai.objectStorage.endpoint" . }}
*/}}
{{- define "onyx-ai.objectStorage.endpoint" -}}
{{- .Values.objectStorage.endpoint | default "" -}}
{{- end -}}

{{/*
Get S3 bucket name.
Always required - validated by onyx-ai.objectStorage.validate.

Usage: {{ include "onyx-ai.objectStorage.bucket" . }}
*/}}
{{- define "onyx-ai.objectStorage.bucket" -}}
{{- .Values.objectStorage.bucket | default "onyx-file-store" -}}
{{- end -}}

{{/*
Get S3 object key prefix.

Usage: {{ include "onyx-ai.objectStorage.prefix" . }}
*/}}
{{- define "onyx-ai.objectStorage.prefix" -}}
{{- .Values.objectStorage.prefix | default "onyx-files" -}}
{{- end -}}

{{/*
Get AWS region.
Returns empty if not set (suitable for self-hosted S3).

Usage: {{ include "onyx-ai.objectStorage.region" . }}
*/}}
{{- define "onyx-ai.objectStorage.region" -}}
{{- .Values.objectStorage.region | default "" -}}
{{- end -}}

{{/*
Get S3 secret name based on configuration mode.
Returns:
- Empty string when useIAM is true (no credentials needed)
- existingSecret when provided
- Auto-generated secret name when inline credentials provided

Usage: {{ include "onyx-ai.objectStorage.secretName" . }}
*/}}
{{- define "onyx-ai.objectStorage.secretName" -}}
{{- if .Values.objectStorage.useIAM -}}
  {{- /* IAM mode - no secret needed */ -}}
  {{- "" -}}
{{- else if .Values.objectStorage.existingSecret -}}
  {{- .Values.objectStorage.existingSecret -}}
{{- else if .Values.objectStorage.accessKey -}}
  {{- /* Inline credentials - use auto-generated secret */ -}}
  {{- printf "%s-external-objectstorage" (include "onyx-ai.fullname" .) -}}
{{- else -}}
  {{- /* No credentials configured - validation will catch this */ -}}
  {{- "" -}}
{{- end -}}
{{- end -}}

{{/*
Check if object storage credentials are needed (not IAM mode).
Returns "true" or "false" as string.

Usage: {{ include "onyx-ai.objectStorage.needsCredentials" . }}
*/}}
{{- define "onyx-ai.objectStorage.needsCredentials" -}}
{{- if .Values.objectStorage.useIAM -}}
  {{- "false" -}}
{{- else -}}
  {{- "true" -}}
{{- end -}}
{{- end -}}

{{/*
Get SSL verification setting.
Returns "true" or "false" as string for S3_VERIFY_SSL env var.

Usage: {{ include "onyx-ai.objectStorage.sslVerify" . }}
*/}}
{{- define "onyx-ai.objectStorage.sslVerify" -}}
{{- if .Values.objectStorage.tls.verify -}}
  {{- "true" -}}
{{- else -}}
  {{- "false" -}}
{{- end -}}
{{- end -}}

{{/*
Validate object storage configuration.
Fails if:
- Bucket name is empty
- Not IAM mode and no credentials provided (neither existingSecret nor inline)

Usage: {{ include "onyx-ai.objectStorage.validate" . }}
*/}}
{{- define "onyx-ai.objectStorage.validate" -}}
{{- /* Validate bucket name is provided */ -}}
{{- if not .Values.objectStorage.bucket -}}
  {{- fail "objectStorage.bucket is required" -}}
{{- end -}}
{{- /* Validate credentials when not using IAM */ -}}
{{- if not .Values.objectStorage.useIAM -}}
  {{- if and (not .Values.objectStorage.existingSecret) (not .Values.objectStorage.accessKey) -}}
    {{- fail "objectStorage.existingSecret or objectStorage.accessKey/secretKey required (or set useIAM: true for IAM role authentication)" -}}
  {{- end -}}
  {{- /* Warn if accessKey provided without secretKey */ -}}
  {{- if and .Values.objectStorage.accessKey (not .Values.objectStorage.secretKey) -}}
    {{- fail "objectStorage.secretKey is required when objectStorage.accessKey is provided" -}}
  {{- end -}}
{{- end -}}
{{- end -}}
