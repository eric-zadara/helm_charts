# argo-examples-onyx

![Version: 0.0.16](https://img.shields.io/badge/Version-0.0.16-informational?style=flat-square)

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| argocdApps | object | `{"annotations":{"argocd.argoproj.io/sync-wave":"20"},"destination":{"server":"https://kubernetes.default.svc"},"namespace":"argocd","project":"default","syncPolicy":{"automated":{"prune":true,"selfHeal":true},"syncOptions":["CreateNamespace=true"]}}` | ArgoCD Application defaults for all applications |
| argocdApps.annotations | object | `{"argocd.argoproj.io/sync-wave":"20"}` | Set default annotations for the application |
| argocdApps.destination | object | `{"server":"https://kubernetes.default.svc"}` | Set default argocd destination configuration |
| argocdApps.namespace | string | `"argocd"` | Set default namespace to put the ArgoCD App CRD into |
| argocdApps.project | string | `"default"` | Set default ArgoCD Project to designate |
| argocdApps.syncPolicy | object | `{"automated":{"prune":true,"selfHeal":true},"syncOptions":["CreateNamespace=true"]}` | Set default syncPolicy for all apps |
| common | object | `{"auth":{"oauthClientID":null,"oauthClientSecret":null,"oauthValidEmailDomains":[],"type":"none"},"ingress":{"clusterIssuer":"selfsigned","enabled":true,"ingressClassName":"traefik","rootDomain":""},"monitoring":{"enabled":false},"redundancy":{"replicas":3},"revisionHistoryLimit":2}` | Set common settings to be used in all applications |
| common.auth.oauthClientID | string | `nil` | OAuth client ID for google |
| common.auth.oauthClientSecret | string | `nil` | OAuth client secret for google |
| common.auth.type | string | `"none"` | Set auth type if application supports it [none|basic|google] |
| common.ingress | object | `{"clusterIssuer":"selfsigned","enabled":true,"ingressClassName":"traefik","rootDomain":""}` | Common defaults applied to ingresses in all applications |
| common.ingress.clusterIssuer | string | `"selfsigned"` | Set default cert-manager cluster-issuer |
| common.ingress.enabled | bool | `true` | Enable ingresses for all applications |
| common.ingress.ingressClassName | string | `"traefik"` | Set default ingressClassName |
| common.ingress.rootDomain | string | `""` | Set root domain to use for ingress rules of all applications |
| common.monitoring | object | `{"enabled":false}` | TODO Set/Enable podMonitor/serviceMonitor |
| common.redundancy | object | `{"replicas":3}` | Set default redundancy configurations |
| common.revisionHistoryLimit | int | `2` | Default revisionHistoryLimit where applicable |
| ollama.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key | string | `"nvidia.com/device-plugin.config"` |  |
| ollama.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].operator | string | `"In"` |  |
| ollama.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[0] | string | `"tesla-25b6"` |  |
| ollama.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[1] | string | `"tesla-2235"` |  |
| ollama.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[2] | string | `"tesla-27b8"` |  |
| ollama.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[3] | string | `"tesla-26b9"` |  |
| ollama.argocdApps.annotations."argocd.argoproj.io/sync-wave" | string | `"11"` |  |
| ollama.config.models | list | `["llama3.1:8b-instruct-q8_0"]` | Set list of models to be preloaded into ollama |
| ollama.enabled | bool | `true` | Enable ollama |
| ollama.resources.limits."nvidia.com/gpu" | int | `8` |  |
| ollama.resources.limits.cpu | int | `8` |  |
| ollama.resources.limits.memory | string | `"20Gi"` |  |
| ollama.resources.requests."nvidia.com/gpu" | int | `8` |  |
| ollama.resources.requests.cpu | int | `4` |  |
| ollama.resources.requests.memory | string | `"15Gi"` |  |
| ollama.targetRevision | string | `"1.4.0"` | Set chart version/revision |
| onyx.chartSource | string | `"helm"` | Set chart source. git/helm |
| onyx.config.configMap.auth | object | `{}` | Configmap for setting Onyx Env Vars for authentication |
| onyx.config.configMap.web | object | `{}` | Configmap for setting Onyx Env Vars related to web |
| onyx.config.index.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key | string | `"nvidia.com/device-plugin.config"` |  |
| onyx.config.index.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].operator | string | `"In"` |  |
| onyx.config.index.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[0] | string | `"tesla-25b6"` |  |
| onyx.config.index.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[1] | string | `"tesla-2235"` |  |
| onyx.config.index.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[2] | string | `"tesla-27b8"` |  |
| onyx.config.index.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[3] | string | `"tesla-26b9"` |  |
| onyx.config.index.resources.limits."nvidia.com/gpu" | int | `4` |  |
| onyx.config.index.resources.requests."nvidia.com/gpu" | int | `4` |  |
| onyx.config.inference.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key | string | `"nvidia.com/device-plugin.config"` |  |
| onyx.config.inference.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].operator | string | `"In"` |  |
| onyx.config.inference.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[0] | string | `"tesla-25b6"` |  |
| onyx.config.inference.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[1] | string | `"tesla-2235"` |  |
| onyx.config.inference.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[2] | string | `"tesla-27b8"` |  |
| onyx.config.inference.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[3] | string | `"tesla-26b9"` |  |
| onyx.config.inference.resources.limits."nvidia.com/gpu" | int | `4` |  |
| onyx.config.inference.resources.requests."nvidia.com/gpu" | int | `4` |  |
| onyx.enabled | bool | `true` | Enable onyx |
| onyx.targetRevision | string | `"0.0.5"` | Set chart version/revision |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
