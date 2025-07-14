# argo-examples-operators

![Version: 0.0.12](https://img.shields.io/badge/Version-0.0.12-informational?style=flat-square)

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| argo-cd.argocdApps.annotations."argocd.argoproj.io/sync-wave" | string | `"1"` |  |
| argo-cd.config.execEnabled | bool | `false` | Enable Argo's build in terminal |
| argo-cd.config.rbac | object | `{}` | Configure RBAC per ArgoCD's helm chart |
| argo-cd.enabled | bool | `true` | Enable/Takeover argocd |
| argo-cd.namespace | string | `"argocd"` | Override default target namespace |
| argo-cd.redundancy.replicas | int | `2` |  |
| argo-cd.targetRevision | string | `"7.7.14"` | Set chart version |
| argocdApps | object | `{"annotations":{"argocd.argoproj.io/sync-wave":"10"},"destination":{"server":"https://kubernetes.default.svc"},"namespace":"argocd","project":"default","syncPolicy":{"automated":{"prune":true,"selfHeal":true},"syncOptions":["CreateNamespace=true","ServerSideApply=true"]}}` | ArgoCD Application defaults for all applications |
| argocdApps.annotations | object | `{"argocd.argoproj.io/sync-wave":"10"}` | Set default annotations for the application. |
| argocdApps.destination | object | `{"server":"https://kubernetes.default.svc"}` | Set default argocd destination configuration |
| argocdApps.namespace | string | `"argocd"` | Set default namespace to put the ArgoCD App CRD into |
| argocdApps.project | string | `"default"` | Set default ArgoCD Project to designate |
| argocdApps.syncPolicy | object | `{"automated":{"prune":true,"selfHeal":true},"syncOptions":["CreateNamespace=true","ServerSideApply=true"]}` | Set default syncPolicy for all apps |
| cert-manager-clusterissuers.argocdApps.annotations."argocd.argoproj.io/sync-wave" | string | `"3"` |  |
| cert-manager-clusterissuers.enabled | bool | `true` | Install default cert-manager ClusterIssuers |
| cert-manager-clusterissuers.namespace | string | `"cert-manager"` | Override default target namespace |
| cert-manager-clusterissuers.targetRevision | string | `"0.0.1"` | Set chart version |
| cert-manager.argocdApps.annotations."argocd.argoproj.io/sync-wave" | string | `"2"` |  |
| cert-manager.enabled | bool | `true` | Enable cert-manager |
| cert-manager.nameOverride | string | `nil` | Override app name |
| cert-manager.targetRevision | string | `"v1.15.3"` | Set chart version |
| cloudnative-pg.argocdApps.annotations."argocd.argoproj.io/sync-wave" | string | `"4"` |  |
| cloudnative-pg.enabled | bool | `true` | Enable CNPG |
| cloudnative-pg.targetRevision | string | `"0.22.0"` | Set chart version |
| common | object | `{"auth":{"oauthClientID":null,"oauthClientSecret":null,"oauthValidEmailDomains":[],"type":"none"},"ingress":{"clusterIssuer":"selfsigned","enabled":false,"ingressClassName":"traefik","rootDomain":""},"monitoring":{"enabled":false,"label":"victoria-metrics-k8s-stack"},"redundancy":{"replicas":3},"revisionHistoryLimit":2}` | Set common settings to be used in all applications |
| common.auth.oauthClientID | string | `nil` | OAuth client ID for google |
| common.auth.oauthClientSecret | string | `nil` | OAuth client secret for google |
| common.auth.type | string | `"none"` | Set auth type if application supports it [none|basic|google] |
| common.ingress | object | `{"clusterIssuer":"selfsigned","enabled":false,"ingressClassName":"traefik","rootDomain":""}` | Common defaults applied to ingresses in all applications |
| common.ingress.clusterIssuer | string | `"selfsigned"` | Set default cert-manager cluster-issuer |
| common.ingress.enabled | bool | `false` | Enable ingresses for all applications |
| common.ingress.ingressClassName | string | `"traefik"` | Set default ingressClassName |
| common.ingress.rootDomain | string | `""` | Set root domain to use for ingress rules of all applications |
| common.monitoring.enabled | bool | `false` | Enable pod/service monitors |
| common.monitoring.label | string | `"victoria-metrics-k8s-stack"` | Override monitor label |
| common.redundancy | object | `{"replicas":3}` | Set default redundancy configurations |
| common.revisionHistoryLimit | int | `2` | Default revisionHistoryLimit where applicable |
| gpu-operator.enabled | bool | `true` | Load gpu-operator |
| gpu-operator.targetRevision | string | `"v24.6.1"` | Set chart version |
| grafana-dashboards.chartSource | string | `"git"` | Set chart source. git/helm |
| grafana-dashboards.enabled | bool | `true` | Load Prom CRDs for Victoria Metrics |
| grafana-dashboards.namespace | string | `"victoria-metrics-k8s-stack"` | Override default target namespace |
| grafana-dashboards.targetRevision | string | `"HEAD"` | Set chart version |
| prometheus-operator-crds.argocdApps.annotations."argocd.argoproj.io/sync-wave" | string | `"2"` |  |
| prometheus-operator-crds.enabled | bool | `true` | Load Prom CRDs for Victoria Metrics |
| prometheus-operator-crds.namespace | string | `"victoria-metrics-k8s-stack"` | Override default target namespace |
| prometheus-operator-crds.targetRevision | string | `"14.0.0"` | Set chart version |
| victoria-metrics-k8s-stack.argocdApps.annotations."argocd.argoproj.io/sync-wave" | string | `"3"` |  |
| victoria-metrics-k8s-stack.config.googleAuthRolePath | string | `nil` | If AUTH is configured, configure `grafana."grafana.ini"."auth.google".role_attribute_path` |
| victoria-metrics-k8s-stack.enabled | bool | `true` | Enable victoria-metrics |
| victoria-metrics-k8s-stack.targetRevision | string | `"0.25.14"` | Set chart version |
