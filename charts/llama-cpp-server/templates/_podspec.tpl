{{/*
Shared container spec for llama-server (image, args, env, ports, probes, resources, volumeMounts).
*/}}
{{- define "llama-cpp-server.containerSpec" -}}
- name: llama-server
  image: "{{ .Values.image.repository }}:{{ include "llama-cpp-server.imageTag" . }}"
  imagePullPolicy: {{ .Values.image.pullPolicy }}
  {{- with .Values.containerSecurityContext }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  ports:
    - name: http
      containerPort: {{ .Values.service.port }}
      protocol: TCP
  args:
    - "--host"
    - "0.0.0.0"
    - "--port"
    - {{ .Values.service.port | quote }}
    {{- /* Model loading args */}}
    {{- if .Values.model.multi.enabled }}
    - "--models-dir"
    - {{ .Values.model.multi.modelsDir | quote }}
    - "--models-preset"
    - "/etc/llama/models-preset.ini"
    - "--models-max"
    - {{ .Values.model.multi.modelsMax | quote }}
    {{- else if and (eq .Values.model.source "hf") (not .Values.model.preload) }}
    - "-hf"
    - {{ .Values.model.hf.repo | quote }}
    {{- if .Values.model.hf.file }}
    - "-hff"
    - {{ .Values.model.hf.file | quote }}
    {{- end }}
    {{- else }}
    - "-m"
    - {{ .Values.model.path | quote }}
    {{- end }}
    {{- if .Values.model.alias }}
    - "-a"
    - {{ .Values.model.alias | quote }}
    {{- end }}
    {{- /* Server config */}}
    {{- if gt (int .Values.server.contextSize) 0 }}
    - "--ctx-size"
    - {{ .Values.server.contextSize | quote }}
    {{- end }}
    {{- if .Values.server.parallel }}
    - "--parallel"
    - {{ .Values.server.parallel | quote }}
    {{- end }}
    {{- if .Values.server.batchSize }}
    - "--batch-size"
    - {{ .Values.server.batchSize | quote }}
    {{- end }}
    {{- if .Values.server.ubatchSize }}
    - "--ubatch-size"
    - {{ .Values.server.ubatchSize | quote }}
    {{- end }}
    {{- if .Values.server.httpThreads }}
    - "--threads-http"
    - {{ .Values.server.httpThreads | quote }}
    {{- end }}
    {{- /* GPU args */}}
    {{- if .Values.gpu.enabled }}
    - "--gpu-layers"
    - {{ .Values.server.gpuLayers | quote }}
    {{- if .Values.server.splitMode }}
    - "--split-mode"
    - {{ .Values.server.splitMode | quote }}
    - "--main-gpu"
    - {{ .Values.server.mainGpu | quote }}
    {{- end }}
    {{- if .Values.server.tensorSplit }}
    - "--tensor-split"
    - {{ .Values.server.tensorSplit | quote }}
    {{- end }}
    {{- /* I4: flashAttention — bare boolean flag, no value */}}
    {{- if .Values.server.flashAttention }}
    - "--flash-attn"
    {{- end }}
    {{- end }}
    {{- /* CPU args */}}
    {{- if .Values.server.threads }}
    - "--threads"
    - {{ .Values.server.threads | quote }}
    {{- end }}
    {{- if .Values.server.threadsBatch }}
    - "--threads-batch"
    - {{ .Values.server.threadsBatch | quote }}
    {{- end }}
    {{- if .Values.server.mlock }}
    - "--mlock"
    {{- end }}
    {{- /* Feature args */}}
    {{- if .Values.server.metrics }}
    - "--metrics"
    {{- end }}
    {{- if .Values.server.embedding }}
    - "--embedding"
    {{- end }}
    {{- if .Values.server.reranking }}
    - "--reranking"
    {{- end }}
    {{- if .Values.server.reasoning }}
    - "--reasoning-format"
    - {{ .Values.server.reasoning | quote }}
    {{- end }}
    {{- if .Values.server.chatTemplate }}
    - "--chat-template"
    - {{ .Values.server.chatTemplate | quote }}
    {{- end }}
    {{- if not .Values.server.warmup }}
    - "--no-warmup"
    {{- end }}
    {{- if .Values.server.offline }}
    - "--offline"
    {{- end }}
    {{- range .Values.extraArgs }}
    - {{ . | quote }}
    {{- end }}
  {{- /* Environment variables — use LLAMA_API_KEY env var instead of --api-key arg */}}
  {{- $hasEnv := or .Values.extraEnv (and (eq .Values.model.source "hf") (not .Values.model.preload) .Values.model.credentials.existingSecret) .Values.server.apiKey .Values.server.apiKeySecret }}
  {{- if $hasEnv }}
  env:
    {{- if and (eq .Values.model.source "hf") (not .Values.model.preload) .Values.model.credentials.existingSecret }}
    - name: HF_TOKEN
      valueFrom:
        secretKeyRef:
          name: {{ .Values.model.credentials.existingSecret }}
          key: {{ get .Values.model.credentials.secretKeys "HF_TOKEN" | default "HF_TOKEN" }}
    {{- end }}
    {{- if .Values.server.apiKeySecret }}
    - name: LLAMA_API_KEY
      valueFrom:
        secretKeyRef:
          name: {{ .Values.server.apiKeySecret }}
          key: api-key
    {{- else if .Values.server.apiKey }}
    - name: LLAMA_API_KEY
      value: {{ .Values.server.apiKey | quote }}
    {{- end }}
    {{- with .Values.extraEnv }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- end }}
  {{- with .Values.extraEnvFrom }}
  envFrom:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- /* Resources with GPU injection */}}
  {{- $resources := deepCopy (.Values.resources | default dict) }}
  {{- if .Values.gpu.enabled }}
  {{- $gpuKey := include "llama-cpp-server.gpuResourceKey" . }}
  {{- if $gpuKey }}
  {{- $limits := $resources.limits | default dict }}
  {{- $_ := set $limits $gpuKey (.Values.gpu.count | toString) }}
  {{- $_ := set $resources "limits" $limits }}
  {{- end }}
  {{- end }}
  {{- if $resources }}
  resources:
    {{- toYaml $resources | nindent 4 }}
  {{- end }}
  volumeMounts:
    - name: model-storage
      mountPath: {{ .Values.persistentVolume.mountPath }}
    {{- if .Values.model.multi.enabled }}
    - name: models-preset
      mountPath: /etc/llama/
      readOnly: true
    {{- end }}
    {{- with .Values.extraVolumeMounts }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- /* I9: preStop hook for graceful drain */}}
  lifecycle:
    preStop:
      exec:
        command: ["sleep", "5"]
  {{- /* Probes */}}
  {{- if .Values.startupProbe.enabled }}
  startupProbe:
    httpGet:
      path: {{ .Values.startupProbe.path }}
      port: http
    initialDelaySeconds: {{ .Values.startupProbe.initialDelaySeconds }}
    periodSeconds: {{ .Values.startupProbe.periodSeconds }}
    timeoutSeconds: {{ .Values.startupProbe.timeoutSeconds }}
    failureThreshold: {{ .Values.startupProbe.failureThreshold }}
  {{- end }}
  {{- if .Values.livenessProbe.enabled }}
  livenessProbe:
    httpGet:
      path: {{ .Values.livenessProbe.path }}
      port: http
    periodSeconds: {{ .Values.livenessProbe.periodSeconds }}
    timeoutSeconds: {{ .Values.livenessProbe.timeoutSeconds }}
    failureThreshold: {{ .Values.livenessProbe.failureThreshold }}
  {{- end }}
  {{- if .Values.readinessProbe.enabled }}
  readinessProbe:
    httpGet:
      path: {{ .Values.readinessProbe.path }}
      port: http
    periodSeconds: {{ .Values.readinessProbe.periodSeconds }}
    timeoutSeconds: {{ .Values.readinessProbe.timeoutSeconds }}
    failureThreshold: {{ .Values.readinessProbe.failureThreshold }}
  {{- end }}
{{- end }}

{{/*
Shared init containers block for model preloading.
*/}}
{{- define "llama-cpp-server.initContainers" -}}
{{- $needsInitSingle := and .Values.model.preload (ne .Values.model.source "") (not .Values.model.multi.enabled) }}
{{- $needsInitMultiDict := dict "val" false }}
{{- if .Values.model.multi.enabled }}
{{- range .Values.model.multi.models }}
{{- if .preload }}
{{- $_ := set $needsInitMultiDict "val" true }}
{{- end }}
{{- end }}
{{- end }}
{{- $needsInitMulti := get $needsInitMultiDict "val" }}
{{- if or $needsInitSingle $needsInitMulti }}
initContainers:
  - name: model-download
    image: "{{ .Values.initContainer.image.repository }}:{{ .Values.initContainer.image.tag }}"
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
    command:
      - /bin/sh
      - -c
      - |
        set -e
        cleanup() { find "{{ .Values.persistentVolume.mountPath | default "/models" }}" -name '*.download.tmp' -delete 2>/dev/null || true; }
        trap cleanup EXIT
        {{- /* I2: HF auth header setup — no eval, explicit if/else for safety */}}
        {{- if $needsInitMulti }}
        {{- range $idx, $m := .Values.model.multi.models }}
        {{- if $m.preload }}
        {{- if eq $m.source "url" }}
        echo "Downloading model $MODEL_NAME_{{ $idx }} from URL..."
        DEST="$MODELS_DIR/$MODEL_NAME_{{ $idx }}.gguf"
        if [ -f "$DEST" ]; then
          echo "  $DEST already exists, skipping."
        else
          TMPFILE="${DEST}.download.tmp"
          curl -fSL --retry 3 --retry-delay 5 -o "$TMPFILE" "$MODEL_URL_{{ $idx }}"
          mv "$TMPFILE" "$DEST"
        fi
        {{- else if eq $m.source "hf" }}
        echo "Downloading model $MODEL_NAME_{{ $idx }} from HuggingFace..."
        {{- if $m.hf.file }}
        DEST="$MODELS_DIR/$MODEL_HF_FILE_{{ $idx }}"
        HF_URL="https://huggingface.co/$MODEL_HF_REPO_{{ $idx }}/resolve/main/$MODEL_HF_FILE_{{ $idx }}"
        {{- else }}
        DEST="$MODELS_DIR/$MODEL_NAME_{{ $idx }}.gguf"
        HF_URL="https://huggingface.co/$MODEL_HF_REPO_{{ $idx }}/resolve/main/$MODEL_NAME_{{ $idx }}.gguf"
        {{- end }}
        if [ -f "$DEST" ]; then
          echo "  $DEST already exists, skipping."
        else
          TMPFILE="${DEST}.download.tmp"
          if [ -n "${HF_TOKEN:-}" ]; then
            curl -fSL --retry 3 --retry-delay 5 -H "Authorization: Bearer $HF_TOKEN" -o "$TMPFILE" "$HF_URL"
          else
            curl -fSL --retry 3 --retry-delay 5 -o "$TMPFILE" "$HF_URL"
          fi
          mv "$TMPFILE" "$DEST"
        fi
        {{- else if eq $m.source "s3" }}
        echo "Downloading model $MODEL_NAME_{{ $idx }} from S3..."
        DEST="$MODELS_DIR/$MODEL_NAME_{{ $idx }}.gguf"
        if [ -f "$DEST" ]; then
          echo "  $DEST already exists, skipping."
        else
          TMPFILE="${DEST}.download.tmp"
        {{- if $m.s3.endpoint }}
          S3_URL="${MODEL_S3_ENDPOINT_{{ $idx }}}/$MODEL_S3_BUCKET_{{ $idx }}/$MODEL_S3_KEY_{{ $idx }}"
        {{- else }}
          S3_URL="https://${MODEL_S3_BUCKET_{{ $idx }}}.s3.${MODEL_S3_REGION_{{ $idx }}:-us-east-1}.amazonaws.com/$MODEL_S3_KEY_{{ $idx }}"
        {{- end }}
          curl -fSL --retry 3 --retry-delay 5 --aws-sigv4 "aws:amz:${MODEL_S3_REGION_{{ $idx }}:-us-east-1}:s3" --user "${AWS_ACCESS_KEY_ID}:${AWS_SECRET_ACCESS_KEY}" -o "$TMPFILE" "$S3_URL"
          mv "$TMPFILE" "$DEST"
        fi
        {{- end }}
        {{- end }}
        {{- end }}
        {{- else }}
        {{- if eq .Values.model.source "url" }}
        echo "Downloading model from URL..."
        if [ -f "$MODEL_DEST" ]; then
          echo "  $MODEL_DEST already exists, skipping."
        else
          TMPFILE="${MODEL_DEST}.download.tmp"
          curl -fSL --retry 3 --retry-delay 5 -o "$TMPFILE" "$MODEL_URL"
          mv "$TMPFILE" "$MODEL_DEST"
        fi
        {{- else if eq .Values.model.source "hf" }}
        echo "Downloading model from HuggingFace..."
        if [ -f "$MODEL_DEST" ]; then
          echo "  $MODEL_DEST already exists, skipping."
        else
          TMPFILE="${MODEL_DEST}.download.tmp"
          if [ -n "${HF_TOKEN:-}" ]; then
            curl -fSL --retry 3 --retry-delay 5 -H "Authorization: Bearer $HF_TOKEN" -o "$TMPFILE" "https://huggingface.co/$MODEL_HF_REPO/resolve/main/$MODEL_HF_FILE"
          else
            curl -fSL --retry 3 --retry-delay 5 -o "$TMPFILE" "https://huggingface.co/$MODEL_HF_REPO/resolve/main/$MODEL_HF_FILE"
          fi
          mv "$TMPFILE" "$MODEL_DEST"
        fi
        {{- else if eq .Values.model.source "s3" }}
        echo "Downloading model from S3..."
        if [ -f "$MODEL_DEST" ]; then
          echo "  $MODEL_DEST already exists, skipping."
        else
          TMPFILE="${MODEL_DEST}.download.tmp"
        {{- if .Values.model.s3.endpoint }}
          S3_URL="${MODEL_S3_ENDPOINT}/$MODEL_S3_BUCKET/$MODEL_S3_KEY"
        {{- else }}
          S3_URL="https://${MODEL_S3_BUCKET}.s3.${AWS_DEFAULT_REGION:-us-east-1}.amazonaws.com/$MODEL_S3_KEY"
        {{- end }}
          curl -fSL --retry 3 --retry-delay 5 --aws-sigv4 "aws:amz:${AWS_DEFAULT_REGION:-us-east-1}:s3" --user "${AWS_ACCESS_KEY_ID}:${AWS_SECRET_ACCESS_KEY}" -o "$TMPFILE" "$S3_URL"
          mv "$TMPFILE" "$MODEL_DEST"
        fi
        {{- end }}
        {{- end }}
        echo "Download complete."
    env:
      {{- if $needsInitMulti }}
      - name: MODELS_DIR
        value: {{ .Values.model.multi.modelsDir | quote }}
      {{- range $idx, $m := .Values.model.multi.models }}
      {{- if $m.preload }}
      {{- /* M7: Pass model names as env vars instead of template interpolation */}}
      - name: MODEL_NAME_{{ $idx }}
        value: {{ $m.name | quote }}
      {{- if eq $m.source "url" }}
      - name: MODEL_URL_{{ $idx }}
        value: {{ $m.url | quote }}
      {{- else if eq $m.source "hf" }}
      - name: MODEL_HF_REPO_{{ $idx }}
        value: {{ $m.hf.repo | quote }}
      {{- if $m.hf.file }}
      - name: MODEL_HF_FILE_{{ $idx }}
        value: {{ $m.hf.file | quote }}
      {{- end }}
      {{- else if eq $m.source "s3" }}
      - name: MODEL_S3_BUCKET_{{ $idx }}
        value: {{ $m.s3.bucket | quote }}
      - name: MODEL_S3_KEY_{{ $idx }}
        value: {{ $m.s3.key | quote }}
      {{- if $m.s3.region }}
      - name: MODEL_S3_REGION_{{ $idx }}
        value: {{ $m.s3.region | quote }}
      {{- end }}
      {{- if $m.s3.endpoint }}
      - name: MODEL_S3_ENDPOINT_{{ $idx }}
        value: {{ $m.s3.endpoint | quote }}
      {{- end }}
      {{- end }}
      {{- end }}
      {{- end }}
      {{- else }}
      - name: MODEL_DEST
        value: {{ .Values.model.path | quote }}
      {{- if eq .Values.model.source "url" }}
      - name: MODEL_URL
        value: {{ .Values.model.url | quote }}
      {{- else if eq .Values.model.source "hf" }}
      - name: MODEL_HF_REPO
        value: {{ .Values.model.hf.repo | quote }}
      - name: MODEL_HF_FILE
        value: {{ .Values.model.hf.file | quote }}
      {{- else if eq .Values.model.source "s3" }}
      - name: MODEL_S3_BUCKET
        value: {{ .Values.model.s3.bucket | quote }}
      - name: MODEL_S3_KEY
        value: {{ .Values.model.s3.key | quote }}
      {{- if .Values.model.s3.region }}
      - name: AWS_DEFAULT_REGION
        value: {{ .Values.model.s3.region | quote }}
      {{- end }}
      {{- if .Values.model.s3.endpoint }}
      - name: MODEL_S3_ENDPOINT
        value: {{ .Values.model.s3.endpoint | quote }}
      {{- end }}
      {{- end }}
      {{- end }}
      {{- if .Values.model.credentials.existingSecret }}
      {{- range $envName, $secretKey := .Values.model.credentials.secretKeys }}
      - name: {{ $envName }}
        valueFrom:
          secretKeyRef:
            name: {{ $.Values.model.credentials.existingSecret }}
            key: {{ $secretKey }}
      {{- end }}
      {{- end }}
    {{- with .Values.initContainer.resources }}
    resources:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    volumeMounts:
      - name: model-storage
        mountPath: {{ .Values.persistentVolume.mountPath }}
{{- end }}
{{- end }}

{{/*
Shared volumes block.
*/}}
{{- define "llama-cpp-server.volumes" -}}
volumes:
  - name: model-storage
    {{- if .Values.persistentVolume.enabled }}
    persistentVolumeClaim:
      claimName: {{ .Values.persistentVolume.existingClaim | default (include "llama-cpp-server.fullname" .) }}
    {{- else }}
    emptyDir: {}
    {{- end }}
  {{- if .Values.model.multi.enabled }}
  - name: models-preset
    configMap:
      name: {{ include "llama-cpp-server.fullname" . }}-models-preset
  {{- end }}
  {{- with .Values.extraVolumes }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end }}

{{/*
Shared pod spec: nodeSelector, tolerations (with NVIDIA auto-append), affinity,
serviceAccountName, imagePullSecrets, securityContext, initContainers, containers, volumes.
*/}}
{{- define "llama-cpp-server.podSpec" -}}
{{- include "llama-cpp-server.validation" . }}
serviceAccountName: {{ include "llama-cpp-server.serviceAccountName" . }}
{{- with .Values.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- if .Values.runtimeClassName }}
runtimeClassName: {{ .Values.runtimeClassName }}
{{- end }}
terminationGracePeriodSeconds: {{ .Values.terminationGracePeriodSeconds }}
{{- with .Values.podSecurityContext }}
securityContext:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- /* Build tolerations: user-defined + auto NVIDIA GPU toleration (M3: with duplicate guard) */}}
{{- $tolerations := .Values.tolerations | default list }}
{{- if and .Values.gpu.enabled (eq .Values.gpu.type "nvidia") }}
{{- $hasNvidiaToleration := dict "found" false }}
{{- range $tolerations }}
{{- if eq (get . "key" | default "") "nvidia.com/gpu" }}
{{- $_ := set $hasNvidiaToleration "found" true }}
{{- end }}
{{- end }}
{{- if not (get $hasNvidiaToleration "found") }}
{{- $nvToleration := dict "key" "nvidia.com/gpu" "operator" "Exists" "effect" "NoSchedule" }}
{{- $tolerations = append $tolerations $nvToleration }}
{{- end }}
{{- end }}
{{- if $tolerations }}
tolerations:
  {{- toYaml $tolerations | nindent 2 }}
{{- end }}
{{- include "llama-cpp-server.initContainers" . | nindent 0 }}
containers:
  {{- include "llama-cpp-server.containerSpec" . | nindent 2 }}
{{- include "llama-cpp-server.volumes" . | nindent 0 }}
{{- end }}
