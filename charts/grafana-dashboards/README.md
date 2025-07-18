# grafana-dashboards

![Version: 0.0.7](https://img.shields.io/badge/Version-0.0.7-informational?style=flat-square)

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| configAnnotations | object | `{}` | Set default annotations for all objects |
| configKind | string | `"ConfigMap"` | Set dashboard kind |
| configLabels | object | `{"grafana_dashboard":""}` | Set default labels for all objects |
| configNamespace | string | `nil` | Set deployment namespace for objects |
| node-exporter.annotations | object | `{}` | Set annotations for objects in dashboards/node-exporter |
| node-exporter.enabled | bool | `false` | Deploy node-exporter dashboards |
| node-exporter.labels | object | `{}` | Set labels for objects in dashboards/node-exporter |
| nvidia.annotations | object | `{}` | Set annotations for objects in dashboards/nvidia |
| nvidia.enabled | bool | `false` | Deploy nvidia dashboards |
| nvidia.labels | object | `{}` | Set labels for objects in dashboards/nvidia |
| vespa.annotations | object | `{}` | Set annotations for objects in dashboards/nvidia |
| vespa.enabled | bool | `false` | Deploy vespa dashboards |
| vespa.labels | object | `{}` | Set labels for objects in dashboards/nvidia |
| zadara.annotations | object | `{}` | Set annotations for objects in dashboards/zadara |
| zadara.enabled | bool | `false` | Deploy Zadara dashboards |
| zadara.labels | object | `{}` | Set labels for objects in dashboards/zadara |
