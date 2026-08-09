# nvidia-device-plugin

Makes `nvidia.com/gpu` schedulable on `orion-ai-01` (DGX Spark, GB10). Talos
system extensions provide the driver/toolkit; this chart provides the
kubelet-facing device plugin plus a `RuntimeClass/nvidia`.

Time-sliced to 4 replicas so `vllm-main` and `vllm-aux`
(`kubernetes/apps/vllm/`) can both request `nvidia.com/gpu: 1` on the single
physical GPU — safe here because memory is unified and both models' footprints
fit; this is scheduling sharing, not hardware partitioning (no MIG).

## Verify

```
kubectl describe node orion-ai-01 | grep -A5 Allocatable   # expect nvidia.com/gpu: 4
```

## Troubleshooting

- **`nvidia.com/gpu` not allocatable:** node plugin pod may not be scheduling —
  check the toleration in `values.yaml` matches the node's actual taint
  (`kubectl describe node orion-ai-01 | grep -A5 Taints`); it's applied by hand,
  not tracked in git.
- **Pods stuck Pending on `nvidia.com/gpu`:** confirm `nodeSelector` matches and
  the device plugin DaemonSet pod is `Running` on `orion-ai-01`.
