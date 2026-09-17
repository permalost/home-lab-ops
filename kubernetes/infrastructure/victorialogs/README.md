# victorialogs

Log storage — `victoria-logs-single`, same vendor as `vkms`. Fed by Vector
(`infrastructure/vector`), queried from Grafana via the
`victoriametrics-logs-datasource` plugin (installed through `vkms`'s
`grafana.plugins`, needs internet access).

No ingress — only Vector and Grafana need to reach it, both in-cluster.
Retention 14d, 10Gi on `rook-ceph-block`.
