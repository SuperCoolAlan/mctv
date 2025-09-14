# MCTV K0s Cluster - Complete Setup Guide

This repository contains everything needed to set up a k0s Kubernetes cluster on a Raspberry Pi 5 with Frigate NVR, Cloudflare Tunnel, and Twingate.

## Prerequisites

### Hardware
- Raspberry Pi 5 (4GB+ RAM recommended)
- MicroSD card (32GB+ recommended)
- (Optional) Google Coral USB TPU for AI object detection
- (Optional) Powered USB 3.0 hub if using Coral USB

### Software Requirements
- Raspberry Pi OS Lite 64-bit (Bookworm)
- SSH enabled on Pi
- macOS/Linux workstation with:
  - `k0sctl` installed (`brew install k0sctl`)
  - `kubectl` installed (`brew install kubectl`)
  - `kustomize` installed (`brew install kustomize`)
  - SSH key at `~/.ssh/momscloset`

## Quick Start - Fresh Install

### 1. Flash Raspberry Pi OS
1. Download Raspberry Pi Imager
2. Flash 64-bit Raspberry Pi OS Lite (Bookworm)
3. Configure in Imager:
   - Hostname: `mctv3`
   - Username: `alan`
   - Enable SSH
   - Configure WiFi if needed

### 2. Initial Pi Setup
```bash
cd setup/

# Run the remote setup script from your workstation
./setup-remote.sh

# Wait for reboot if cgroups were configured
# The Pi will reboot automatically if needed
```

### 3. Deploy k0s Cluster
```bash
# After Pi has rebooted (if it did)
./deploy.sh

# Select option 1 for full deployment
# This will:
# - Set up SSH authentication
# - Deploy k0s cluster
# - Configure single-node cluster (remove taint)
# - Save kubeconfig
```

### 4. (Optional) Install Coral USB Support
If you have a Google Coral USB TPU:

```bash
# SSH into the Pi
ssh -i ~/.ssh/momscloset alan@mctv3.local

# Run the Coral setup script
sudo bash /home/alan/setup-coral-usb.sh

# This installs the Edge TPU runtime at reduced frequency (safer)
# Unplug and replug the Coral USB after installation
```

### 5. Deploy Applications

```bash
# Set the kubeconfig
export KUBECONFIG=~/.kube/clusters/mctv3.yaml

# Deploy in this order:

# 1. Cloudflare Tunnel (for external access)
cd k0s/cloudflare-tunnel/
kustomize build --enable-exec --enable-alpha-plugins . | kubectl apply -f -

# 2. Frigate NVR (camera system)
cd ../frigate/
kustomize build --enable-exec --enable-alpha-plugins . | kubectl apply -f -

# 3. Twingate (VPN access)
cd ../twingate/
kustomize build --enable-exec --enable-alpha-plugins . | kubectl apply -f -
```

### 6. Configure Cloudflare Tunnel Routes

1. Go to [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
2. Navigate to **Networks** → **Tunnels**
3. Find your tunnel and click **Configure**
4. Add public hostname:
   - Subdomain: `momscloset`
   - Domain: `asandov.com`
   - Service: `https://frigate.frigate.svc.cluster.local:8971`
   - Enable "No TLS Verify"

### 7. Access Frigate

1. Get the admin password:
   ```bash
   kubectl logs -n frigate deployment/frigate | grep "Password:"
   ```

2. Access at: https://momscloset.asandov.com
   - Username: `admin`
   - Password: (from logs)

## Detailed Setup Steps

### Network Configuration
The Pi should be on network `10.0.1.x`. If using WiFi:
```bash
cd setup/
./wifi-config.sh
```

### Verifying Installation
```bash
# Check cluster health
./validate.sh

# Check all pods
kubectl get pods -A

# Check specific services
kubectl logs -n cloudflare deployment/cloudflared
kubectl logs -n frigate deployment/frigate
kubectl logs -n twingate deployment/mctv3-connector
```

## Troubleshooting

### k0s Won't Start
- Check cgroups: `cat /proc/cgroups | grep memory`
- If missing, rerun setup script and reboot

### Cloudflare Tunnel Not Connecting
- Check token is correct in `k0s/cloudflare-tunnel/secrets/tunnel-token-secret.enc.yaml`
- Verify tunnel shows "Healthy" in Cloudflare dashboard

### Frigate Can't Access Coral
- Check Coral is detected: `lsusb | grep -E "(Google|18d1)"`
- Verify Edge TPU runtime: `dpkg -l | grep libedgetpu`
- Use powered USB hub if getting disconnections

### Pods Stuck or Crashing
- Check resources: `kubectl top nodes`
- Review logs: `kubectl logs -n <namespace> <pod-name>`
- Raspberry Pi may need more resources

## Important Files

- **Kubeconfig**: `~/.kube/clusters/mctv3.yaml`
- **Cluster config**: `setup/cluster.yaml`
- **Secrets encryption**: GPG key `29FE211C0F0BF17C10EFEB150ECC79FC3C76B242`

## Security Notes

- All secrets are encrypted with SOPS
- Frigate has authentication enabled
- Cloudflare Tunnel provides secure external access
- No ports need to be opened on your router

## Maintenance

### Updating Services
```bash
cd k0s/<service>/
# Edit values-override.yaml
kustomize build --enable-exec --enable-alpha-plugins . | kubectl apply -f -
```

### Backup
```bash
cd setup/
./backup-restore.sh
```

## Support

For issues:
1. Check service logs
2. Run validation script: `./validate.sh`
3. Review service-specific README files in k0s/*/