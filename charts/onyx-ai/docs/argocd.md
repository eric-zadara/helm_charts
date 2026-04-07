# Deploying onyx-ai with ArgoCD

This chart works with ArgoCD, but there are a few things to know up front
because the chart uses Helm features that interact non-obviously with
ArgoCD's `helm template` rendering model.

## TL;DR checklist

- [ ] `argocd-repo-server` can reach the four subchart repos (see
  [Subchart dependency resolution](#subchart-dependency-resolution))
- [ ] Your `argocd-application-controller` service account can create
  cluster-scoped resources (see
  [Cluster-scoped RBAC](#cluster-scoped-rbac))
- [ ] Your `Application` manifest includes `ignoreDifferences` for the
  three wrapper-managed credential secrets (see
  [Credential secrets use Helm lookup](#credential-secrets-use-helm-lookup))
- [ ] You're aware that the garage bootstrap Job is an argocd Sync
  hook, not a tracked resource (see
  [Bootstrap Job is an ArgoCD Sync hook](#bootstrap-job-is-an-argocd-sync-hook))

## Credential secrets use Helm `lookup`

Three wrapper templates generate random credentials on first apply and
then re-read the live Secret on subsequent renders so the password stays
stable across upgrades:

- `templates/garage-credentials-secret.yaml` (S3 access key + secret)
- `templates/valkey-credentials-secret.yaml` (Valkey default-user password)
- `templates/redis-ha-secret.yaml` (Spotahome Redis HA password)

All three use Helm's `lookup` function, which **returns `nil` under
`helm template`** (the mode ArgoCD uses) because there's no cluster
context during rendering. That means without intervention, **every
argocd sync will regenerate a fresh random password** and update the
Secret, causing:

- Credential churn: pods running with the old password, new pods
  (scale-up, rollouts) getting the new one, intermittent auth failures.
- For `garage-credentials`: the bootstrap Job would import a new key
  into garage on every sync; old keys accumulate in garage storage.

### Fix: `ignoreDifferences` in your Application manifest

Tell argocd to leave these secrets alone after the first apply. Add
this block to the `spec.ignoreDifferences` of your `Application`:

```yaml
spec:
  ignoreDifferences:
    - group: ""
      kind: Secret
      name: onyx-ai-garage-credentials
      jsonPointers:
        - /data
        - /stringData
    - group: ""
      kind: Secret
      name: onyx-ai-valkey-credentials
      jsonPointers:
        - /data
        - /stringData
    # Only needed if redis.ha.enabled: true
    - group: ""
      kind: Secret
      name: onyx-ai-redis-ha
      jsonPointers:
        - /data
        - /stringData
```

Replace `onyx-ai-` with your actual release name if different.

After the first sync, argocd will apply each Secret once and then stop
diffing them. The wrapper's `lookup`-based persistence still works for
`helm upgrade` users; argocd users just opt out of the re-render behavior.

### Recommended for production: External Secrets Operator integration

The chart ships an opt-in [external-secrets-operator](https://external-secrets.io/)
integration. When enabled, the wrapper renders `ExternalSecret` CRs
instead of the lookup-based `Secret` templates, and ESO populates the
target Secret from your upstream backend (Vault, AWS Secrets Manager,
GCP Secret Manager, 1Password Connect, etc.). ESO becomes the owner of
the Secret, so **ArgoCD never sees a credential diff and the
`ignoreDifferences` block above is no longer needed for the
ESO-managed secrets.**

#### Prerequisites

1. external-secrets-operator installed in the cluster
2. A `SecretStore` (namespaced) or `ClusterSecretStore` (cluster-scoped)
   pointing at your backend, e.g. a Vault `ClusterSecretStore` named
   `vault-backend`
3. The backend populated with the values described in the
   "Backend layout" subsection below

#### Minimal values.yaml — Vault example

Assume a `ClusterSecretStore` named `vault-backend` with a Vault KV v2
mount at `secret/`, and the following pre-created secret paths:

- `secret/onyx-ai/garage` containing fields `accessKey` and `secretKey`
- `secret/onyx-ai/valkey` containing field `password`

```yaml
externalSecrets:
  enabled: true
  secretStoreRefKind: ClusterSecretStore
  secretStoreRefName: vault-backend
  refreshInterval: "1h"

  garage:
    enabled: true
    remoteRefs:
      s3_aws_access_key_id:
        key: secret/data/onyx-ai/garage
        property: accessKey
      s3_aws_secret_access_key:
        key: secret/data/onyx-ai/garage
        property: secretKey
      garage_access_key_id:
        key: secret/data/onyx-ai/garage
        property: accessKey
      garage_secret_access_key:
        key: secret/data/onyx-ai/garage
        property: secretKey

  valkey:
    enabled: true
    remoteRefs:
      default-password:
        key: secret/data/onyx-ai/valkey
        property: password
```

The `s3_aws_*` and `garage_*` keys typically map to the same backend
property — the duplication exists because the Onyx S3 client and the
Garage CLI use different conventions for the same credential pair.

#### Backend layout — keys ESO must populate

**Garage** (target secret: `{fullname}-garage-credentials`):

| Target key in K8s Secret    | Required | Typical backend field |
| --------------------------- | -------- | --------------------- |
| `s3_aws_access_key_id`      | yes      | `accessKey`           |
| `s3_aws_secret_access_key`  | yes      | `secretKey`           |
| `garage_access_key_id`      | yes      | `accessKey` (same)    |
| `garage_secret_access_key`  | yes      | `secretKey` (same)    |

**Valkey** (target secret: `{fullname}-valkey-credentials`):

| Target key in K8s Secret  | Required | Typical backend field |
| ------------------------- | -------- | --------------------- |
| `default-password`        | yes      | `password`            |

#### Selective migration

The two per-secret toggles (`externalSecrets.garage.enabled` and
`externalSecrets.valkey.enabled`) are independent. You can adopt ESO
for garage first, leave Valkey on the wrapper's lookup-based
auto-generation, and migrate Valkey later — or vice versa. The
skip-guard on the wrapper's `garage-credentials-secret.yaml` only
fires when ESO is BOTH globally enabled AND the per-secret toggle is on.

#### Out of scope

The Spotahome `RedisFailover` password secret (`{fullname}-redis-ha`,
created when `redis.ha.enabled: true`) is NOT covered by the ESO
integration in v0.2.0. If you use HA Redis, you still need an
`ignoreDifferences` block for that one secret. Tracking note in
`templates/redis-ha-secret.yaml`.

#### Further reading

- ESO documentation: <https://external-secrets.io>
- SecretStore vs ClusterSecretStore:
  <https://external-secrets.io/latest/api/secretstore/>
- ExternalSecret reference:
  <https://external-secrets.io/latest/api/externalsecret/>

### Alternative: pre-create secrets out of band

If you'd rather not run external-secrets-operator at all, you can
pre-create the credential secrets with any tool of your choice
([sealed-secrets](https://github.com/bitnami-labs/sealed-secrets),
plain `kubectl create secret`, etc.) and disable both the wrapper's
lookup-based generation and the ESO integration:

1. Pre-create secrets with the expected names
   (`{release}-garage-credentials`, `{release}-valkey-credentials`,
   optionally `{release}-redis-ha`) and the expected keys (see
   `values.yaml` comments on `onyx.auth.objectstorage.secretKeys` /
   `onyx.auth.redis.secretKeys`).
2. Set `onyx.auth.*.existingSecret` to point at the pre-created secret
   names. The wrapper validation will accept these and the
   `lookup`-based templates will re-emit their values from the live
   cluster on subsequent renders.

## Bootstrap Job is an ArgoCD Sync hook

The garage bootstrap Job (`{release}-garage-bootstrap-r1` under argocd)
is annotated as an argocd Sync hook:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/hook: Sync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
    argocd.argoproj.io/sync-wave: "1"
```

This is deliberate:

- **Sync hook, not tracked resource**: argocd does not report drift
  when the Job is garbage-collected by its `ttlSecondsAfterFinished`,
  so you don't get endless "OutOfSync" reconciliation loops after the
  bootstrap runs once.
- **`BeforeHookCreation`**: on every sync, argocd deletes any previous
  hook Job with the same name and creates a fresh one. This avoids
  ever hitting Job-spec immutability.
- **`sync-wave: "1"`**: runs after the credentials Secret and bootstrap
  ConfigMap (`sync-wave: "-1"`), alongside the main workloads
  (`sync-wave: 0` default).

The hook is idempotent — it polls garage's admin API until reachable,
then uses `CreateBucket` / `ImportKey` / `AllowBucketKey` operations
that all treat 409 Conflict ("already exists") as success. Re-running
the bootstrap on every argocd sync is safe and takes ~20 seconds.

> **Note:** These annotations are invisible to `helm install` /
> `helm upgrade`, which continue to see a regular Job managed via
> `.Release.Revision`-suffixed names. Both execution models work.

## Sync-wave ordering

The chart uses three argocd sync waves:

| Wave | Resources | Purpose |
|------|-----------|---------|
| `-1` | Credentials secrets (garage, valkey, redis-ha, external-*), bootstrap ConfigMap | Exist before anything references them |
| `0` (default) | All main workloads (garage StatefulSet, valkey Deployment, onyx api/web/celery, opensearch, vespa, CNPG Cluster), services, PVCs | Main sync phase |
| `1` | Traefik ingress / middleware, garage bootstrap Job (as a Sync hook) | Applied after the main workloads land |

The bootstrap Job deliberately doesn't wait for main workloads to be
**Ready** before running — it polls garage's admin API internally and
retries until reachable. This means onyx pods may briefly show
`CrashLoopBackOff` with S3 `AccessDenied` errors while the bootstrap is
still granting permissions; they self-heal on the next kubelet restart
once garage's ACL is correct.

## Cluster-scoped RBAC

The garage subchart (`datahub-local/garage-helm`) creates a
`ClusterRole` and `ClusterRoleBinding` with permissions to manage
`deuxfleurs.fr/garagenodes` custom resources. If your
`argocd-application-controller` runs with namespace-scoped RBAC or a
restricted service account, sync will fail with an RBAC error on these
cluster-scoped resources.

The standard fix is to run `argocd-application-controller` with a
service account bound to a ClusterRole that includes at minimum:

```yaml
apiGroups: ["rbac.authorization.k8s.io"]
resources: ["clusterroles", "clusterrolebindings"]
verbs: ["create", "update", "patch", "delete", "get", "list", "watch"]
```

Most ArgoCD installations (including the upstream
`argocd/argo-cd` chart's default) already grant this via the
`argocd-application-controller` ClusterRole. If you've locked it down
further, you'll need to add these verbs back for the garage path to work.

## Subchart dependency resolution

The chart has four subchart dependencies pinned in `Chart.lock`:

- `onyx` at `https://onyx-dot-app.github.io/onyx/`
- `cluster` (CNPG) at `https://cloudnative-pg.github.io/charts`
- `garage` at `https://datahub-local.github.io/garage-helm`
- `valkey` at `https://valkey.io/valkey-helm/`

ArgoCD's `argocd-repo-server` runs `helm dependency build` before
`helm template` when it sees a chart with dependencies and a
`Chart.lock`. This requires **outbound network access from
`argocd-repo-server` to all four repository URLs**.

For **air-gapped clusters**, either:

1. Stand up a local ChartMuseum / Harbor / JFrog chart repo, mirror the
   four charts there, and override the `repository:` URLs in
   `Chart.yaml` to point at your mirror, OR
2. Vendor the subchart tarballs directly into `charts/onyx-ai/charts/`
   (bypassing the gitignore) and commit them. This trades reproducibility
   for air-gap friendliness.

## Sample Application manifest

Here's a complete `Application` you can adapt. Replace `REPO_URL`,
`TARGET_NAMESPACE`, and `INGRESS_HOSTNAME` with your values.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: onyx-ai
  namespace: argocd
  # Helpful for keeping your Application yaml ordered in ArgoCD's UI
  annotations:
    argocd.argoproj.io/sync-wave: "10"
spec:
  project: default
  source:
    repoURL: REPO_URL
    targetRevision: main
    path: charts/onyx-ai
    helm:
      releaseName: onyx-ai
      # Uncomment to pass values inline instead of using valueFiles:
      # values: |
      #   ingress:
      #     enabled: true
      #     host: onyx.example.com
      valueFiles:
        - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: TARGET_NAMESPACE
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      # Skip revision history entries for resources that are expected
      # to churn (none here by default, but a useful default).
      - RespectIgnoreDifferences=true
    retry:
      limit: 10
      backoff:
        duration: 30s
        factor: 2
        maxDuration: 10m
  # CRITICAL: tells argocd to stop re-applying our lookup-managed
  # credential secrets after the first sync. Without this, every sync
  # would regenerate random passwords and churn the secrets.
  ignoreDifferences:
    - group: ""
      kind: Secret
      name: onyx-ai-garage-credentials
      jsonPointers:
        - /data
        - /stringData
    - group: ""
      kind: Secret
      name: onyx-ai-valkey-credentials
      jsonPointers:
        - /data
        - /stringData
```

### Notes on the sample

- `CreateNamespace=true` is convenient for first-time installs.
- `ServerSideApply=true` is recommended because the CNPG subchart emits
  large CRD objects that tend to exceed the client-side apply annotation
  size limit.
- `selfHeal: true` will re-sync the bootstrap Job if anyone manually
  deletes it, but argocd won't churn on TTL cleanup because of the
  Sync hook annotation.
- The `ignoreDifferences` block only covers garage + valkey by default.
  Add the `onyx-ai-redis-ha` entry if you enable `redis.ha.enabled`.
- `retry.limit: 10` gives the initial install enough room to tolerate
  slow garage / postgres startup on cold clusters. The `maxDuration: 10m`
  caps total retry time.

## Troubleshooting under ArgoCD

### Application stuck "Progressing" with CrashLoopBackOff on onyx pods

Most likely cause: the garage bootstrap Job hasn't completed yet. Check:

```bash
kubectl -n TARGET_NAMESPACE get jobs -l app.kubernetes.io/component=garage-bootstrap
kubectl -n TARGET_NAMESPACE logs -l app.kubernetes.io/component=garage-bootstrap --tail=50
```

You should see `[bootstrap] bootstrap complete` in the logs within about
a minute of garage becoming Ready. If you don't:

- Garage pod may still be pulling the image (`dxflrs/garage:v2.2.0`) on
  a slow network; the bootstrap retries 30 times with 5s backoff by
  default (tunable under `garage.bootstrap.stepRetries` /
  `stepBackoffSeconds`).
- The bootstrap's Pod may have hit its `backoffLimit` (default 6). In
  that case the Job is `Failed` and you need to inspect the pod logs,
  resolve the underlying issue (usually garage admin API unreachable),
  and re-sync.

### Application reports "out of sync" on Secret stringData

Your `ignoreDifferences` block is missing or mis-named. Compare the
Secret names in the diff against the recipe above. Common mistakes:

- Using a custom release name and forgetting to update the secret
  names in `ignoreDifferences` (`{release}-garage-credentials` etc.).
- Forgetting `onyx-ai-redis-ha` when `redis.ha.enabled: true`.

### Application reports "RBAC error" creating ClusterRole

See [Cluster-scoped RBAC](#cluster-scoped-rbac) above. The garage
subchart needs to create cluster-scoped RBAC for its `garagenodes` CRs.
