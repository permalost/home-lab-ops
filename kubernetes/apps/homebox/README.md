# homebox

Home inventory management application. Built on the shared `webapp` base with a dedicated PVC for data persistence.

## Configuration

- **Namespace:** `homebox`
- Uses `../webapp/base` as a Kustomize base with `namePrefix: homebox-` and the shared `ingress` component.
- PVC defined in `pvc.yaml` for persistent data storage.

## Dependencies

Longhorn or another storage class must be available for PVC provisioning.

## Ingress / Endpoints

Exposed via the webapp `ingress` component (see `../webapp/components/ingress`).

## Troubleshooting

- **Data loss after restart:** Verify the PVC is bound and the pod is mounting it correctly (`kubectl describe pod -n homebox`).
