# vector

DaemonSet log shipper — `kubernetes_logs` source, `elasticsearch` sink to
`victorialogs` (VictoriaLogs's Elasticsearch-compatible ingest API; no
native VictoriaLogs sink exists in Vector). Tolerates the control-plane
taint so it runs on every node.
