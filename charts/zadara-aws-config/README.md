# zadara-aws-config

![Version: 0.0.3](https://img.shields.io/badge/Version-0.0.3-informational?style=flat-square)

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| default.region | string | `"us-east-1"` | Default region string |
| default.signingRegion | string | `"us-east-1"` | Default region string used for signing |
| endpointUrl | string | `"https://cloud.zadara.com"` | Default root endpoint |
| global | object | `{}` | cloud.conf `[Global]` stanza |
| serviceOverrides | object | `{"autoscaling":{"Url":"{{ .Values.endpointUrl }}/api/v2/aws/autoscaling"},"ec2":{"Url":"{{ .Values.endpointUrl }}/api/v2/aws/ec2"},"elasticloadbalancing":{"Url":"{{ .Values.endpointUrl }}/api/v2/aws/elbv2"}}` | Definition for all ServiceOverrides and their attributes, overrides any defaults from above |
