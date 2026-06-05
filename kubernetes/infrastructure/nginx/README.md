# nginx

Ingress controller (ingress-nginx) for HTTP/HTTPS routing. Set as the default ingress class. Used primarily on the **na** cluster; on **orion** the `cilium` ingressClass is used instead.

## Configuration

- **Chart:** `ingress-nginx/ingress-nginx` (latest)
- **Namespace:** `networking`
- **Values source:** HelmRelease inline

Key overrides:
- `controller.setAsDefaultIngress: true` — nginx is the default ingress class
- `controller.metrics.enabled: true` — Prometheus metrics exposed on port 10254
- HSTS disabled (`hsts: false`) — intentional; TLS termination and HSTS headers are handled upstream (router/firewall), not at the ingress layer

A cluster-wide ConfigMap (`configMap.yaml`) provides nginx configuration overrides.

## Dependencies

Requires a LoadBalancer IP (from MetalLB on na, or Cilium L2 on orion) to get an external IP.

## Ingress / Endpoints

Exposes HTTP (80) and HTTPS (443) on a LoadBalancer IP. All apps using `ingressClassName: nginx` route through this controller.

## Troubleshooting

- **502 Bad Gateway:** The backend pod is not ready or the Service selector is wrong.
- **No external IP on the nginx Service:** MetalLB pool is exhausted or not running.
- **Ingress not picking up:** Verify `ingressClassName: nginx` is set on the Ingress resource.
