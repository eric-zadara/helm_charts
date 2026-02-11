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
  - Pooler service: {release}-postgresql-cluster-pooler-rw (pooler named "rw")

Usage: {{ include "onyx-ai.postgresql.host" . }}
*/}}
{{- define "onyx-ai.postgresql.host" -}}
{{- if not .Values.cnpg.enabled -}}
  {{- /* External PostgreSQL mode */ -}}
  {{- required "externalPostgresql.host is required when cnpg.enabled is false" .Values.externalPostgresql.host -}}
{{- else if .Values.cnpg.pooler.enabled -}}
  {{- /* CNPG Pooler creates service: {cluster}-pooler-{pooler-name} */ -}}
  {{- /* Our pooler is named "rw" in postgresql-cluster.poolers[0].name */ -}}
  {{- printf "%s-postgresql-cluster-pooler-rw" .Release.Name -}}
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
Priority: External > HA > Default Valkey

For each mode:
- External: Uses externalRedis.host directly
- HA (Spotahome): Uses rfr-{release}-redis-ha (Redis pods, not Sentinel)
- Default (Valkey): Uses {release}-valkey-primary (Bitnami Valkey service)

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
  {{- /* Default Valkey (Bitnami): {release}-valkey-primary */ -}}
  {{- printf "%s-valkey-primary" .Release.Name -}}
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
- HA: Wrapper-generated secret ({fullname}-redis-ha)
- Default (Valkey): {release}-valkey (Bitnami Valkey auto-generated secret)

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
  {{- /* Valkey (Bitnami): {release}-valkey */ -}}
  {{- printf "%s-valkey" .Release.Name -}}
{{- end -}}
{{- end -}}

{{/*
Get Redis secret key name.
The key name within the secret that contains the password.
- Default (Valkey): valkey-password (Bitnami Valkey convention)
- HA: redis_password (Spotahome convention)
- External: redis_password (conventional)

Usage: {{ include "onyx-ai.redis.secretKey" . }}
*/}}
{{- define "onyx-ai.redis.secretKey" -}}
{{- if or .Values.externalRedis.host .Values.redis.ha.enabled -}}
  {{- "redis_password" -}}
{{- else -}}
  {{- "valkey-password" -}}
{{- end -}}
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
  {{- $modeNames = append $modeNames "redis.enabled (Valkey)" -}}
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
Object Storage Helper Functions (Phase 5, updated Phase 8.4 for GarageFS)
================================================================================
*/}}

{{/*
Get S3 endpoint URL.
When garage.enabled, returns GarageFS S3 API service URL.
Otherwise returns empty string for AWS S3, or configured endpoint for self-hosted.

Usage: {{ include "onyx-ai.objectStorage.endpoint" . }}
*/}}
{{- define "onyx-ai.objectStorage.endpoint" -}}
{{- if .Values.garage.enabled -}}
  {{- /* GarageFS S3 API service: {release}-garage:3900 */ -}}
  {{- printf "http://%s-garage:3900" .Release.Name -}}
{{- else -}}
  {{- .Values.objectStorage.endpoint | default "" -}}
{{- end -}}
{{- end -}}

{{/*
Get S3 bucket name.
When garage.enabled, returns release-scoped bucket name for multi-tenancy.
Otherwise returns objectStorage.bucket.

Usage: {{ include "onyx-ai.objectStorage.bucket" . }}
*/}}
{{- define "onyx-ai.objectStorage.bucket" -}}
{{- if .Values.garage.enabled -}}
  {{- .Values.garage.bucket | default (printf "%s-files" .Release.Name) -}}
{{- else -}}
  {{- .Values.objectStorage.bucket | default "onyx-file-store" -}}
{{- end -}}
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
- GarageFS credentials secret when garage.enabled
- Empty string when useIAM is true (no credentials needed)
- existingSecret when provided
- Auto-generated secret name when inline credentials provided

Usage: {{ include "onyx-ai.objectStorage.secretName" . }}
*/}}
{{- define "onyx-ai.objectStorage.secretName" -}}
{{- if .Values.garage.enabled -}}
  {{- printf "%s-garage-credentials" (include "onyx-ai.fullname" .) -}}
{{- else if .Values.objectStorage.useIAM -}}
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
GarageFS always needs credentials (auto-generated).

Usage: {{ include "onyx-ai.objectStorage.needsCredentials" . }}
*/}}
{{- define "onyx-ai.objectStorage.needsCredentials" -}}
{{- if .Values.garage.enabled -}}
  {{- /* GarageFS provides its own credentials */ -}}
  {{- "true" -}}
{{- else if .Values.objectStorage.useIAM -}}
  {{- "false" -}}
{{- else -}}
  {{- "true" -}}
{{- end -}}
{{- end -}}

{{/*
Get SSL verification setting.
Returns "true" or "false" as string for S3_VERIFY_SSL env var.
GarageFS uses HTTP internally, so SSL verify is false when garage.enabled.

Usage: {{ include "onyx-ai.objectStorage.sslVerify" . }}
*/}}
{{- define "onyx-ai.objectStorage.sslVerify" -}}
{{- if .Values.garage.enabled -}}
  {{- /* GarageFS internal: no TLS */ -}}
  {{- "false" -}}
{{- else if .Values.objectStorage.tls.verify -}}
  {{- "true" -}}
{{- else -}}
  {{- "false" -}}
{{- end -}}
{{- end -}}

{{/*
Validate object storage configuration.
Fails if:
- Both garage.enabled AND external objectStorage configured (mutual exclusion)
- Bucket name is empty (when garage not enabled)
- Not IAM mode and no credentials provided (when garage not enabled)

Usage: {{ include "onyx-ai.objectStorage.validate" . }}
*/}}
{{- define "onyx-ai.objectStorage.validate" -}}
{{- if .Values.garage.enabled -}}
  {{- /* Mutual exclusion check: garage OR external, not both */ -}}
  {{- if or .Values.objectStorage.endpoint .Values.objectStorage.existingSecret .Values.objectStorage.accessKey -}}
    {{- fail "Cannot use both garage.enabled: true and external objectStorage configuration. Choose one: either set garage.enabled: true OR configure objectStorage.* (not both)." -}}
  {{- end -}}
{{- else -}}
  {{- /* Original external storage validation */ -}}
  {{- if not .Values.objectStorage.bucket -}}
    {{- fail "objectStorage.bucket is required" -}}
  {{- end -}}
  {{- if not .Values.objectStorage.useIAM -}}
    {{- if and (not .Values.objectStorage.existingSecret) (not .Values.objectStorage.accessKey) -}}
      {{- fail "objectStorage.existingSecret or objectStorage.accessKey/secretKey required (or set useIAM: true for IAM role authentication, or set garage.enabled: true for built-in storage)" -}}
    {{- end -}}
    {{- if and .Values.objectStorage.accessKey (not .Values.objectStorage.secretKey) -}}
      {{- fail "objectStorage.secretKey is required when objectStorage.accessKey is provided" -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
================================================================================
Credential Wiring Validation (Phase 8.2)
================================================================================
*/}}

{{/*
Validate PostgreSQL credential wiring.
Fails if CNPG is enabled but auth.postgresql.existingSecret is not configured.

Usage: {{ include "onyx-ai.postgresql.validateCredentials" . }}
*/}}
{{- define "onyx-ai.postgresql.validateCredentials" -}}
{{- if .Values.cnpg.enabled -}}
  {{- $expectedSecret := printf "%s-postgresql-cluster-app" .Release.Name -}}
  {{- $configuredSecret := .Values.onyx.auth.postgresql.existingSecret | default "" -}}
  {{- if eq $configuredSecret "" -}}
    {{- fail (printf "onyx.auth.postgresql.existingSecret is required when cnpg.enabled is true. Set to: %s" $expectedSecret) -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
Validate Redis credential wiring.
Fails if HA mode or external Redis is enabled but auth.redis.existingSecret is not configured.

Usage: {{ include "onyx-ai.redis.validateCredentials" . }}
*/}}
{{- define "onyx-ai.redis.validateCredentials" -}}
{{- if and .Values.redis.enabled (not .Values.redis.ha.enabled) (not .Values.externalRedis.host) -}}
  {{- /* Default Valkey mode - validate auth wiring */ -}}
  {{- $expectedSecret := printf "%s-valkey" .Release.Name -}}
  {{- $configuredSecret := .Values.onyx.auth.redis.existingSecret | default "" -}}
  {{- if eq $configuredSecret "" -}}
    {{- fail (printf "onyx.auth.redis.existingSecret is required when using Valkey (redis.enabled: true). Set to: %s" $expectedSecret) -}}
  {{- end -}}
{{- end -}}
{{- if .Values.redis.ha.enabled -}}
  {{- $expectedSecret := printf "%s-redis-ha" (include "onyx-ai.fullname" .) -}}
  {{- $configuredSecret := .Values.onyx.auth.redis.existingSecret | default "" -}}
  {{- if eq $configuredSecret "" -}}
    {{- fail (printf "onyx.auth.redis.existingSecret is required when redis.ha.enabled is true. Set to: %s" $expectedSecret) -}}
  {{- end -}}
{{- end -}}
{{- if .Values.externalRedis.host -}}
  {{- $configuredSecret := .Values.onyx.auth.redis.existingSecret | default "" -}}
  {{- if eq $configuredSecret "" -}}
    {{- $autoSecret := printf "%s-external-redis" (include "onyx-ai.fullname" .) -}}
    {{- if .Values.externalRedis.existingSecret -}}
      {{- fail (printf "onyx.auth.redis.existingSecret is required when externalRedis.host is set. Set to: %s" .Values.externalRedis.existingSecret) -}}
    {{- else -}}
      {{- fail (printf "onyx.auth.redis.existingSecret is required when externalRedis.host is set. Set to: %s" $autoSecret) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
Validate GarageFS credential wiring.
Fails if garage.enabled=true but auth.objectstorage.existingSecret is not configured.

Usage: {{ include "onyx-ai.garage.validateCredentials" . }}
*/}}
{{- define "onyx-ai.garage.validateCredentials" -}}
{{- if .Values.garage.enabled -}}
  {{- $expectedSecret := printf "%s-garage-credentials" (include "onyx-ai.fullname" .) -}}
  {{- $configuredSecret := .Values.onyx.auth.objectstorage.existingSecret | default "" -}}
  {{- if eq $configuredSecret "" -}}
    {{- fail (printf "onyx.auth.objectstorage.existingSecret is required when garage.enabled is true. Set to: %s" $expectedSecret) -}}
  {{- end -}}
{{- end -}}
{{- end -}}

