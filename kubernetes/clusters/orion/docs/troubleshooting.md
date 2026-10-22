# Troubleshooting a service on orion

Read-only. Diagnose with `kubectl` and `flux get`, then fix through a PR. Never apply, edit, delete or restart by hand.

## 1. Did Flux apply it?

```sh
flux get kustomizations              # READY False / stuck revision: read the message
flux get helmreleases -A
kubectl -n flux-system describe kustomization <app>
```

- `kustomize build failed` / `var substitution failed`: run `task test:build` locally; look for an unresolved `${...}`.
- `decryption` errors: the secret file isn't named `*.sops.yaml`/`secret.yaml`, or isn't encrypted.
- `dependency '<x>' is not ready`: fix `<x>` first.
- HelmRelease failing: `kubectl -n <ns> describe helmrelease <name>`; compare against its `values.yaml`.

## 2. Is the workload healthy?

```sh
kubectl -n <ns> get pods
kubectl -n <ns> describe pod <pod>                 # state, restarts, probe failures, OOMKilled
kubectl -n <ns> get events --sort-by=.lastTimestamp
kubectl -n <ns> logs <pod> --tail=200
kubectl -n <ns> logs <pod> --previous              # crash loop: the last terminated container
```

| Symptom | Look for |
|---|---|
| `Pending` | PVC unbound (`get pvc`, storage class `rook-ceph-block`), node resources, taints |
| `ImagePullBackOff` | wrong image/tag, registry reachability |
| `CrashLoopBackOff` | `--previous` logs, missing env/secret key, wrong container port |
| `OOMKilled` | raise the memory limit in `patches/deploy-update-resources.yaml` |
| Running but not ready | readiness probe path/port vs the app |

## 3. Is it reachable?

```sh
kubectl -n <ns> get svc,endpoints
kubectl -n <ns> get httproute <name> -o yaml       # status.parents: Accepted / ResolvedRefs
kubectl -n gateway get gateway
kubectl -n <ns> get certificate -A                 # the wildcard cert lives in the gateway namespace
```

- Service has no endpoints: selector labels don't match the pod, or no pod is ready.
- HTTPRoute not accepted: the namespace lacks the `gateway.networking.k8s.io/access: "true"` label (the `httproute` component adds it to the app's Namespace), or the backend port doesn't match the Service.
- Service port isn't 8080: patch both the Service and the HTTPRoute backend port.

## 4. Report

Write the cause, one or two pieces of evidence (a log line, an event) and the fix. If the fix is a small manifest change in this repo, open a PR. If it needs a node change, a credential or hardware, stop and hand it to a human.
