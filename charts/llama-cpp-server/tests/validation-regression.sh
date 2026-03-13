#!/usr/bin/env bash
# Regression tests for llama-cpp-server Helm chart validation guards.
# Ensures all fail() conditions in _validation.tpl fire on invalid input
# and all CI values files render cleanly on valid input.
#
# Usage: ./tests/validation-regression.sh
# Requirements: helm 3.x
set -euo pipefail

CHART_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
TOTAL=0

# ── Helpers ──────────────────────────────────────────────────────────────

assert_fail() {
  local description="$1"
  shift
  TOTAL=$((TOTAL + 1))
  local output
  if output=$(helm template test "$CHART_DIR" "$@" 2>&1); then
    echo "FAIL  [should reject] $description"
    FAIL=$((FAIL + 1))
  else
    echo "PASS  [rejects]       $description"
    PASS=$((PASS + 1))
  fi
}

assert_pass() {
  local description="$1"
  shift
  TOTAL=$((TOTAL + 1))
  local output
  if output=$(helm template test "$CHART_DIR" "$@" 2>&1); then
    echo "PASS  [renders]       $description"
    PASS=$((PASS + 1))
  else
    echo "FAIL  [should render] $description"
    echo "      $output" | head -3
    FAIL=$((FAIL + 1))
  fi
}

# ── Negative tests: validation guards must fire ──────────────────────────

echo "=== Negative tests: invalid configs must be rejected ==="
echo ""

# Single-model source validation
assert_fail "HF source without repo" \
  --set model.source=hf --set model.hf.repo=""

assert_fail "S3 source without bucket" \
  --set model.source=s3 --set model.s3.key=obj.gguf

assert_fail "S3 source without key" \
  --set model.source=s3 --set model.s3.bucket=my-bucket --set model.s3.key=""

assert_fail "URL source without url" \
  --set model.source=url --set model.url=""

assert_fail "HF preload without file" \
  --set model.source=hf --set model.hf.repo=org/repo --set model.preload=true --set model.hf.file=""

# Multi-model validation
assert_fail "Multi-model enabled without models list" \
  --set model.multi.enabled=true

assert_fail "Multi-model HF preload without file" \
  --set model.multi.enabled=true \
  --set 'model.multi.models[0].name=test' \
  --set 'model.multi.models[0].source=hf' \
  --set 'model.multi.models[0].preload=true' \
  --set 'model.multi.models[0].hf.repo=org/repo'

assert_fail "Multi-model S3 preload without bucket" \
  --set model.multi.enabled=true \
  --set 'model.multi.models[0].name=test' \
  --set 'model.multi.models[0].source=s3' \
  --set 'model.multi.models[0].preload=true' \
  --set 'model.multi.models[0].s3.key=obj.gguf'

assert_fail "Multi-model S3 preload without key" \
  --set model.multi.enabled=true \
  --set 'model.multi.models[0].name=test' \
  --set 'model.multi.models[0].source=s3' \
  --set 'model.multi.models[0].preload=true' \
  --set 'model.multi.models[0].s3.bucket=my-bucket'

assert_fail "Multi-model URL preload without url" \
  --set model.multi.enabled=true \
  --set 'model.multi.models[0].name=test' \
  --set 'model.multi.models[0].source=url' \
  --set 'model.multi.models[0].preload=true'

# GPU validation
assert_fail "GPU enabled with count=0" \
  --set gpu.enabled=true --set gpu.count=0

assert_fail "Vulkan GPU without vulkanResource" \
  --set gpu.enabled=true --set gpu.type=vulkan --set gpu.vulkanResource=""

# PVC + scaling validation
assert_fail "RWO PVC with replicaCount > 1" \
  --set replicaCount=2 --set persistentVolume.enabled=true

assert_fail "RWO PVC with autoscaling enabled" \
  --set autoscaling.enabled=true --set persistentVolume.enabled=true \
  --set server.apiKey=test

assert_fail "Knative + RWO PVC" \
  --set knative.enabled=true --set persistentVolume.enabled=true

# Incompatibility validation
assert_fail "NetworkPolicy + Knative" \
  --set networkPolicy.enabled=true --set knative.enabled=true \
  --set persistentVolume.enabled=false

# Ingress authentication validation
assert_fail "Ingress without authentication" \
  --set ingress.enabled=true --set server.apiKey="" --set server.apiKeySecret="" \
  --set 'ingress.hosts[0].host=test.local' \
  --set 'ingress.hosts[0].paths[0].path=/' \
  --set 'ingress.hosts[0].paths[0].pathType=Prefix'

# ── Positive tests: all CI values files must render ──────────────────────

echo ""
echo "=== Positive tests: CI values files must render cleanly ==="
echo ""

for f in "$CHART_DIR"/ci/*.yaml; do
  assert_pass "$(basename "$f")" -f "$f"
done

# ── Summary ──────────────────────────────────────────────────────────────

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
