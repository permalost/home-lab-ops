# external-endpoints

Routes cluster-external hosts (LAN devices, VMs, anything not running as a
Pod) through the orion Gateway with a real cert, using the standard
Kubernetes "Service without selector" pattern: a Service with no selector
paired with a hand-written EndpointSlice pointing at the external IP. TLS
comes from the Gateway's existing wildcard cert — no per-app Certificate
needed. This has nothing Cilium-specific about it beyond Cilium being the
Gateway API implementation; it's plain Kubernetes.

All forwarded hosts share one namespace (`external-endpoints`) and one Flux
Kustomization, since none of this owns Pods, PVCs, or secrets worth
isolating — see `opensprinkler/` for a working example.

## Adding one

```bash
cp -r kubernetes/apps/external-endpoints/_template kubernetes/apps/external-endpoints/<name>
cd kubernetes/apps/external-endpoints/<name>
for f in *.tmpl; do mv "$f" "${f%.tmpl}"; done
sed -i '' \
  -e 's/__NAME__/<name>/g' \
  -e 's/__ADDRESS__/<ip>/g' \
  -e 's/__PORT__/<port>/g' \
  -e 's/__SUBDOMAIN__/<subdomain>/g' \
  -e 's/__DISPLAY_NAME__/<Display Name>/g' \
  -e 's/__DESCRIPTION__/<description>/g' \
  -e 's/__ICON__/<icon>.png/g' \
  *.yaml
```

Then add `<name>` to `resources:` in `../kustomization.yaml`. No new Flux
Kustomization, no namespace, no cert — it rides the existing ones. Run
`task gen:validate` before pushing.
