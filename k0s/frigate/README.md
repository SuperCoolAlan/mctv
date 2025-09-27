# Frigate NVR Deployment on K0s

This directory contains the Kustomize configuration for deploying Frigate NVR with Coral EdgeTPU support on your k0s cluster.

## Overview

Frigate is deployed with:
- Coral EdgeTPU USB support for hardware-accelerated object detection
- NGINX proxy to handle Cloudflare CORS issues
- OpenEBS storage for recordings and configuration
- SOPS-encrypted secrets management
- Continuous recording with intelligent retention policies

## Directory Structure

```
frigate/
├── README.md                           # This file
├── CLOUDFLARE_CORS_FIX.md             # Documentation for CORS fix
├── kustomization.yaml                  # Main Kustomize configuration
├── values-override.yaml                # Helm chart overrides
├── resources/
│   ├── namespace.yaml                  # Frigate namespace
│   ├── pvcs.yaml                      # PersistentVolumeClaims
│   ├── nginx-proxy-configmap.yaml     # NGINX proxy configuration
│   └── nginx-proxy-deployment.yaml    # NGINX proxy deployment
├── patches/
│   ├── coral-usb-patch.yaml           # Coral USB device support
│   └── env-secrets-patch.yaml         # Environment secrets injection
├── secrets/
│   ├── camera-credentials.enc.yaml    # SOPS-encrypted camera credentials
│   └── frigate-users-config-unused.enc.yaml
└── secrets-generator.yaml             # KSOPS generator configuration
```

## Prerequisites

1. k0s cluster with OpenEBS storage configured
2. kubectl with KUBECONFIG set: `export KUBECONFIG=~/.kube/clusters/mctv3.yaml`
3. Kustomize with KSOPS plugin installed
4. Coral EdgeTPU USB device connected to node
5. SOPS with GPG key: `29FE211C0F0BF17C10EFEB150ECC79FC3C76B242`

## Current Configuration

### Camera: Reolink (10.0.1.18)
- **Main stream**: 1920x1080 for recording
- **Sub stream**: Lower quality for detection
- **Detection**: 5 FPS with Coral EdgeTPU
- **Recording**: Continuous with motion-based retention

### Recording Retention
- **All recordings**: 14 days
- **Motion alerts**: 30 days
- **Motion detections**: 30 days

### Storage
- **Config**: 5Gi PVC on OpenEBS
- **Media**: 100Gi PVC on OpenEBS (mounted at `/media/frigate`)

### Authentication
- Admin password reset disabled (check initial deployment logs)
- Trusted proxies configured for Cloudflare and Kubernetes networks
- IPv6 addresses filtered by NGINX proxy to prevent crashes

## Deployment

### Deploy Frigate
```bash
# Set kubeconfig
export KUBECONFIG=~/.kube/clusters/mctv3.yaml

# Build and apply with KSOPS
kustomize build --enable-exec --enable-alpha-plugins . | kubectl apply -f -

# Wait for pod to be ready
kubectl wait --for=condition=ready pod -n frigate -l app.kubernetes.io/name=frigate --timeout=120s
```

### Verify Deployment
```bash
# Check pods
kubectl get pods -n frigate

# View logs
kubectl logs -n frigate deployment/frigate

# Check recordings
kubectl exec -n frigate deployment/frigate -- ls -la /media/frigate/recordings/
```

## Access Methods

### Via Cloudflare Tunnel (Production)
- URL: https://momscloset.asandov.com
- Configured in Cloudflare Zero Trust dashboard
- Routes to: `http://frigate-nginx-proxy.frigate.svc.cluster.local:8080`

### Local Port Forward (Testing)
```bash
kubectl port-forward -n frigate svc/frigate 5000:5000
# Access at http://localhost:5000
```

## Managing Secrets

### View encrypted secrets
```bash
sops --decrypt secrets/camera-credentials.enc.yaml
```

### Edit encrypted secrets
```bash
sops secrets/camera-credentials.enc.yaml
```

### Create new encrypted secret
```bash
# Create plain secret
cat > secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
  namespace: frigate
stringData:
  key: value
EOF

# Encrypt it
sops --encrypt --pgp 29FE211C0F0BF17C10EFEB150ECC79FC3C76B242 secret.yaml > secrets/my-secret.enc.yaml

# Clean up
rm secret.yaml
```

## Updating Configuration

### Change camera or recording settings
1. Edit `values-override.yaml`
2. Apply changes:
   ```bash
   kustomize build --enable-exec --enable-alpha-plugins . | kubectl apply -f -
   ```

### Update Helm chart version
1. Edit `kustomization.yaml` and change the version
2. Check [blakeshome-charts](https://github.com/blakeblackshear/blakeshome-charts) for latest version

## NGINX Proxy for CORS

The deployment includes an NGINX proxy that:
1. Filters out problematic Cloudflare analytics scripts
2. Strips IPv6 addresses from X-Forwarded-For headers (prevents Frigate auth crashes)
3. Sets permissive CSP headers

See `CLOUDFLARE_CORS_FIX.md` for details.

## Troubleshooting

### Login fails from mobile (IPv6 error)
- Already fixed by NGINX proxy IPv6 filtering
- Check nginx proxy logs: `kubectl logs -n frigate deployment/frigate-nginx-proxy`

### CORS errors in browser console
- Normal - Cloudflare analytics blocked but Frigate works fine
- Can be disabled in Cloudflare dashboard if needed

### No recordings appearing
- Check storage: `kubectl exec -n frigate deployment/frigate -- df -h /media/frigate`
- Verify camera credentials in logs
- Ensure camera is accessible from cluster network

### Coral EdgeTPU not detected
- Verify USB device on node: `kubectl debug node/<nodename> -it --image=busybox -- lsusb`
- Check coral-usb-patch.yaml is applied
- May need to restart Frigate pod after plugging in Coral

### Pod stuck in pending
- Check PVC status: `kubectl get pvc -n frigate`
- Verify OpenEBS is running: `kubectl get pods -n openebs`

## Resources

- [Frigate Documentation](https://docs.frigate.video/)
- [Frigate Configuration Reference](https://docs.frigate.video/configuration/)
- [Helm Chart](https://github.com/blakeblackshear/blakeshome-charts/tree/master/charts/frigate)
- [KSOPS Documentation](https://github.com/viaduct-ai/kustomize-sops)