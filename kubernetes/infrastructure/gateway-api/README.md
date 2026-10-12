# gateway-api

Gateway API CRDs, vendored from `kubernetes-sigs/gateway-api` **v1.6.3**, standard channel
(`config/crd/standard/gateway.networking.k8s.io_<name>.yaml`). Cilium's operator disables its Gateway
controller at startup if the required CRDs are missing or too old (Cilium 1.20 needs v1.6.x and all of:
gatewayclasses, gateways, httproutes, referencegrants, grpcroutes, backendtlspolicies, tlsroutes), and
the Gateway then stops serving TLS.

When bumping Cilium or these CRDs:
- Take the version from Cilium's Gateway API docs for the target release, not from the latest upstream.
- Update `operator.podAnnotations.gateway-api-crds` in `../cilium/values.yaml` so the operator restarts
  and re-checks (it only checks at startup).
- The `cilium` Kustomization depends on `gateway-api`, so the CRDs land first.
