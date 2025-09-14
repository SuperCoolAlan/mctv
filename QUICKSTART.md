# Quick Start Guide

## Prerequisites
1. Raspberry Pi 5 with fresh Raspberry Pi OS Lite 64-bit (Bookworm)
2. Configured in Pi Imager with:
   - Hostname: `mctv3`
   - Username: `alan`
   - SSH enabled
3. SSH key at `~/.ssh/momscloset`
4. Coral USB Accelerator plugged into Pi

## Installation

### Option 1: Automated (Recommended)
```bash
cd /path/to/mctv
./INSTALL.sh
```

### Option 2: Manual Steps
```bash
# 1. Initial Pi setup
cd setup
./setup-remote.sh
# Wait for reboot if needed

# 2. Deploy k0s
./deploy-dynamic.sh

# 3. Deploy services
export KUBECONFIG=~/.kube/clusters/mctv3.yaml
cd ../k0s/local-path-provisioner && kustomize build --enable-exec --enable-alpha-plugins . | kubectl apply -f -
cd ../cloudflare-tunnel && kustomize build --enable-exec --enable-alpha-plugins . | kubectl apply -f -
cd ../frigate && kustomize build --enable-exec --enable-alpha-plugins . | kubectl apply -f -
cd ../twingate && kustomize build --enable-exec --enable-alpha-plugins . | kubectl apply -f -
```

## Post-Installation

1. **Get Frigate Password**:
   ```bash
   export KUBECONFIG=~/.kube/clusters/mctv3.yaml
   kubectl logs -n frigate deployment/frigate | grep -i "password:"
   ```

2. **Plug in Coral USB** when all services are running

3. **Access Frigate**:
   - URL: https://momscloset.asandov.com
   - Username: `admin`
   - Password: (from step 1)

## Verify Everything Works

```bash
# Check all pods running
kubectl get pods -A

# Check Coral detected
kubectl logs -n frigate deployment/frigate | grep "TPU found"

# Test Cloudflare tunnel
curl -I https://momscloset.asandov.com
# Should return 401 Unauthorized
```

## Troubleshooting

See [GOTCHAS.md](GOTCHAS.md) for common issues and fixes.