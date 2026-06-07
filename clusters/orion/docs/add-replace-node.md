# Add or Replace a Node

## Adding a new worker node

1. Add the new node to `NODES.md` (hostname, MAC, disk by-id, IPs).

2. Add a new entry to `talconfig.yaml` under `nodes:`:
   ```yaml
   - hostname: orion-w-03
     ipAddress: 10.50.0.23
     controlPlane: false
     installDisk: /dev/disk/by-path/pci-0000:04:00.0-nvme-1
     networkInterfaces:
       - deviceSelector:
           hardwareAddr: "aa:bb:cc:dd:ee:ff"
         dhcp: false
         vlans:
           - vlanId: 50
             mtu: 1500
             dhcp: false
             addresses:
               - 10.50.0.23/24
             routes:
               - network: 0.0.0.0/0
                 gateway: 10.50.0.1
           - vlanId: 10
             mtu: 1500
             dhcp: false
             addresses:
               - 10.10.0.23/24
     patches:
       - "@./patches/nodes/orion-w-03.yaml"
   ```

3. Create `patches/nodes/orion-w-03.yaml`:
   ```yaml
   machine:
     certSANs:
       - 10.50.0.23
       - 10.10.0.23
       - orion-w-03.norseamerican.com
   ```

4. Re-render and apply:
   ```bash
   task talos:gen-config
   task talos:validate
   task talos:apply NODE=orion-w-03 IP=10.50.0.23 INSECURE=true
   ```

## Replacing a failed node (same hardware type)

If the replacement hardware is identical (same MAC or you're updating the MAC in `talconfig.yaml`):

1. Remove the failed node from Kubernetes:
   ```bash
   kubectl drain orion-w-01 --ignore-daemonsets --delete-emptydir-data --force
   kubectl delete node orion-w-01
   ```

2. If it was a control-plane node, remove from etcd first:
   ```bash
   talosctl -n 10.50.0.10 etcd remove-member <id>
   ```

3. Update `NODES.md` and `talconfig.yaml` if the replacement has a different MAC.

4. Re-render, apply to the replacement node (`INSECURE=true` since it boots fresh from ISO), and verify it joins the cluster.
