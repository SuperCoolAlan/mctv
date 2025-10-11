# Installation Divergences from README

## Issues Encountered

### 1. Missing Control-Plane Toleration for Local-Path-Provisioner
**Issue**: Local-path-provisioner pods couldn't schedule on single-node k0s cluster
**Error**: `0/1 nodes are available: 1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }`
**Fix Required**: Add deployment-patch.yaml with toleration for control-plane nodes

### 2. WiFi Configuration Missing from INSTALL.sh
**Issue**: Initial INSTALL.sh did not configure WiFi, causing Pi to be inaccessible after reboot
**Fix Applied**: Added WiFi configuration to phase1_pi_setup() in INSTALL.sh

### 3. Confirmation Prompts Not Handled
**Issue**: Multiple scripts require interactive confirmations that weren't handled by simple printf
**Scripts Affected**:
- setup-remote.sh (requires multiple "y" confirmations)
- deploy.sh (menu selection followed by confirmations)
**Note**: Eventually bypassed by following README.md workflow directly

### 4. SOPS Decryption Failures
**Issue**: Cloudflare tunnel deployment failed with "Error getting data key"
**Root Cause**: User typed GPG key password incorrectly too many times
**Fix**: Not a real issue - just need to unlock GPG key properly
**Note**: KSOPS works fine when GPG key is properly unlocked

### 5. NVMe Support Not in Original Scripts
**Issue**: Raspberry Pi 5 with NVMe drive requires PCIe enablement
**Fix Applied**: Added comprehensive NVMe support to pi5-k0s-setup-auto.sh including:
- PCIe enablement via dtparam=pciex1
- NVMe formatting and mounting
- k0s data directory on NVMe

### 6. Control-Plane Taint on Single-Node Cluster
**Issue**: All deployments fail to schedule on single-node k0s cluster due to control-plane taint
**Affected Services**: local-path-provisioner, cloudflare-tunnel, frigate, twingate
**Error**: `0/1 nodes are available: 1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }`
**Fix Applied**: Remove taint from node: `kubectl taint nodes mctv3 node-role.kubernetes.io/control-plane:NoSchedule-`
**Proper Fix**: Configure k0s cluster.yaml to not add the taint for single-node deployments

## Recommended Fixes

1. **Configure k0s to not add control-plane taint** for single-node deployments in cluster.yaml
2. **Update local-path-provisioner kustomization.yaml** to include deployment-patch.yaml by default
3. **Ensure WiFi configuration** is always run in INSTALL.sh phase1
4. **Document exact confirmation sequences** needed for each script
5. **Include NVMe detection and setup** in main setup scripts
6. **Add post-deployment step** to remove control-plane taint for single-node clusters