# Known Issues and Fixes

## Issues We Encountered and Fixed

### 1. Hardcoded IP Addresses
**Problem**: k0sctl adds `--kubelet-extra-args=--node-ip=<IP>` which breaks when moving networks
**Fix**: The `deploy-dynamic.sh` script monitors and removes this flag during deployment

### 2. Wrong cmdline.txt Path
**Problem**: Raspberry Pi OS Bookworm uses `/boot/firmware/cmdline.txt` not `/boot/cmdline.txt`
**Fix**: Updated `pi5-k0s-setup.sh` to check both locations

### 3. Missing cgroup_enable=cpuset
**Problem**: k0s requires cpuset cgroup in addition to memory
**Fix**: Added both `cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1`

### 4. Storage Class Required
**Problem**: Frigate needs PersistentVolumes but k0s doesn't include a storage provisioner
**Fix**: Added local-path-provisioner deployment

### 5. Control Plane Taint
**Problem**: Single-node cluster has control-plane taint preventing pod scheduling
**Fix**: Remove taint after deployment with `kubectl taint nodes --all node-role.kubernetes.io/control-plane-`

### 6. Frigate Port Confusion
**Problem**: Port 5000 has no auth, port 8971 requires HTTPS
**Fix**: Use port 8971 with HTTPS in Cloudflare tunnel config

### 7. CPU Detector Crashes with EdgeTPU Model
**Problem**: CPU detector can't load EdgeTPU model file
**Fix**: Remove CPU detector when Coral is available

### 8. Coral Setup Script Interactive Prompts
**Problem**: Script waits for user input when Coral not detected
**Fix**: Made script non-interactive by removing read prompts

### 9. Cloudflare Dashboard vs Local Config
**Problem**: Dashboard settings override local tunnel config
**Fix**: Ensure dashboard is set to `https://frigate.frigate.svc.cluster.local:8971`

## Quick Fixes Cheatsheet

```bash
# Remove hardcoded IP from k0s service
ssh -i ~/.ssh/momscloset alan@mctv3.local "sudo sed -i 's/--kubelet-extra-args=--node-ip=[0-9.]*//g' /etc/systemd/system/k0scontroller.service && sudo systemctl daemon-reload && sudo systemctl restart k0scontroller"

# Fix cgroups if missing
ssh -i ~/.ssh/momscloset alan@mctv3.local "sudo sed -i 's/$/ cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1/' /boot/firmware/cmdline.txt && sudo reboot"

# Remove control-plane taint
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

# Check Coral USB
ssh -i ~/.ssh/momscloset alan@mctv3.local "lsusb | grep -E '(Google|18d1)'"

# Get Frigate password
kubectl logs -n frigate deployment/frigate | grep -i "password:"
```