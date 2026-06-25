# Retiring Vespa (chart 0.4.x → 0.5.0 / Onyx v4)

Onyx v4 (chart `0.6.x`, wrapped by onyx-ai `0.5.0`) retires the bundled Vespa
search engine and makes OpenSearch the sole document index. This chart no
longer renders Vespa, and `onyx.configMap.ONYX_DISABLE_VESPA` is set to
`"true"` so the Onyx backend does not instantiate `VespaIndex`.

## Why this is safe (no reindex, no data loss)

Since v3 this chart ran in **dual-write** mode: OpenSearch received all index
writes (`ENABLE_OPENSEARCH_INDEXING_FOR_ONYX=true`) **and** served all
retrieval (`ENABLE_OPENSEARCH_RETRIEVAL_FOR_ONYX=true`). OpenSearch therefore
already holds the complete, live index; Vespa was kept only to satisfy the v3
code path. Dropping it requires no re-indexing.

## Decommission the live `da-vespa` StatefulSet

The chart stops *rendering* Vespa, but the running `da-vespa` StatefulSet and
its PersistentVolumes still exist in the cluster. Retire them **manually** —
do not rely on ArgoCD auto-prune, which would delete the PV irreversibly via
automation. Substitute your release namespace for `<ns>`.

1. Confirm OpenSearch retrieval is healthy: search returns results in the Onyx
   UI, and the `onyx-ai-opensearch` cluster is green.

2. Confirm the rendered Onyx configmap disables Vespa and keeps OpenSearch as
   the index:
   ```bash
   kubectl get cm -n <ns> onyx-env-configmap -o yaml \
     | grep -E 'ONYX_DISABLE_VESPA|ENABLE_OPENSEARCH|VESPA'
   ```
   Expect `ONYX_DISABLE_VESPA: "true"`, both `ENABLE_OPENSEARCH_*` flags
   `"true"`, and no `VESPA_HOST`.

3. Sync the v4 release. The api-server must come up without Vespa — verify it
   is **not** logging connection-refused on `localhost:19071`.

4. Delete the legacy StatefulSet and its PVCs (data loss here is expected and
   safe; OpenSearch holds the index). Check the PV reclaim policy first.
   ```bash
   kubectl get statefulset -n <ns> da-vespa
   kubectl get pvc -n <ns> -l app=vespa            # verify the label before deleting
   kubectl delete statefulset da-vespa -n <ns>
   kubectl delete pvc -l app=vespa -n <ns>
   ```

5. Verify the underlying PVs are `Released`/reclaimed per their reclaim policy.

## Note on the chart's `legacyVespaCheck`

The upstream subchart ships a `legacyVespaCheck` that fails `helm upgrade` if a
`da-vespa` StatefulSet is still present, to prevent accidental data loss. It
uses Helm's `lookup`, so it is **inert under ArgoCD** (`helm template` returns
no live cluster state). For a direct `helm upgrade` after step 4, set
`onyx.legacyVespaCheck.acknowledged=true` to bypass it once Vespa is gone.
