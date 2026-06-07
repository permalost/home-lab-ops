#!/bin/bash

# Test script to verify consolidated patches generate same output
# This script compares original vs consolidated approaches

set -e

echo "Testing Talos configuration generation..."

# Create temporary directories
mkdir -p test-output/original test-output/consolidated

echo "=== Original approach (using existing patches) ==="
echo "Command would be:"
echo "talosctl gen config orion https://10.50.0.10:6443 \\"
echo "  --config-patch \"@patches/common.yaml\" \\"
echo "  --config-patch \"@patches/controlplane-common.yaml\" \\"
echo "  --config-patch \"@patches/network-vlan.yaml\" \\"
echo "  --config-patch \"@patches/cilium.yaml\" \\"
echo "  --config-patch \"@orion-cp-03.yaml\" \\"
echo "  --output-dir test-output/original"

echo ""
echo "=== Consolidated approach (using new patches) ==="
echo "Command would be:"
echo "talosctl gen config orion https://10.50.0.10:6443 \\"
echo "  --config-patch \"@patches/controlplane.yaml\" \\"
echo "  --config-patch \"@patches/hardware/beelink.yaml\" \\"
echo "  --config-patch \"@patches/cilium.yaml\" \\"
echo "  --config-patch \"@nodes-consolidated/controlplane/orion-cp-03.yaml\" \\"
echo "  --output-dir test-output/consolidated"

echo ""
echo "=== Worker comparison ==="
echo "Original worker command:"
echo "talosctl gen config orion https://10.50.0.10:6443 \\"
echo "  --config-patch \"@patches/common.yaml\" \\"
echo "  --config-patch \"@patches/network-vlan.yaml\" \\"
echo "  --config-patch \"@patches/cilium.yaml\" \\"
echo "  --config-patch \"@orion-w-01.yaml\" \\"
echo "  --output-dir test-output/original-worker"

echo ""
echo "Consolidated worker command:"
echo "talosctl gen config orion https://10.50.0.10:6443 \\"
echo "  --config-patch \"@patches/worker.yaml\" \\"
echo "  --config-patch \"@patches/hardware/bosgame.yaml\" \\"
echo "  --config-patch \"@patches/cilium.yaml\" \\"
echo "  --config-patch \"@nodes-consolidated/worker/orion-w-01.yaml\" \\"
echo "  --output-dir test-output/consolidated-worker"

echo ""
echo "Files created for testing:"
echo "- Consolidated patches: patches/controlplane.yaml, patches/worker.yaml"
echo "- Hardware configs: patches/hardware/beelink.yaml, patches/hardware/bosgame.yaml"
echo "- Example node configs: nodes-consolidated/controlplane/orion-cp-03.yaml"
echo "- Example worker config: nodes-consolidated/worker/orion-w-01.yaml"
echo ""
echo "Run the actual talosctl commands above to verify output matches."
