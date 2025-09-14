# Frigate Deployment on k0s

This directory contains the Kustomize configuration for deploying Frigate NVR on your k0s cluster.

## Prerequisites

1. k0s cluster running (completed via setup scripts)
2. kubectl configured with kubeconfig
3. Kustomize installed (`brew install kustomize`)
4. (Optional) NGINX Ingress Controller for external access

## Files

- `kustomization.yaml` - Main Kustomize configuration that references the Helm chart
- `values-override.yaml` - Custom values that override the Helm chart defaults
- `namespace.yaml` - Creates the frigate namespace
- `coral-usb-patch.yaml` - Patch for Coral USB device support

## Configuration

### 1. Authentication Configuration

Frigate has authentication enabled by default in `values-override.yaml`:

```yaml
auth:
  enabled: true
  reset_admin_password: true
```

On first deployment, check logs for the generated admin password:
```bash
kubectl logs -n frigate deployment/frigate | grep "admin password"
```

### 2. Configure Storage

Adjust storage sizes based on your needs:

```yaml
persistence:
  media:
    size: 50Gi  # Adjust for your recording storage needs
```

### 3. Add Camera Configuration

Add your camera streams in `values-override.yaml`:

```yaml
config: |
  cameras:
    front_door:
      ffmpeg:
        inputs:
          - path: rtsp://username:password@camera-ip:554/stream
            roles:
              - detect
              - record
```

## Deployment

### Deploy with Kustomize

```bash
# Preview what will be deployed
kubectl kustomize k0s/frigate/

# Deploy to cluster
kustomize build --enable-exec --enable-alpha-plugins k0s/frigate/ | kubectl apply -f -

# Or use kustomize with KSOPS for secrets
kustomize build --enable-exec --enable-alpha-plugins k0s/frigate/ | kubectl apply -f -
```

### Verify Deployment

```bash
# Check if pods are running
kubectl get pods -n frigate

# Check ingress
kubectl get ingress -n frigate

# Check services
kubectl get svc -n frigate

# View logs
kubectl logs -n frigate deployment/frigate
```

### Access Frigate

Through Cloudflare Tunnel:
- https://momscloset.asandov.com (with authentication)

The service is exposed on two ports:
- Port 5000: HTTP without authentication (internal use only)
- Port 8971: HTTPS with authentication (used by Cloudflare tunnel)

For local testing without ingress:
```bash
kubectl port-forward -n frigate svc/frigate 5000:5000
# Access at http://localhost:5000
```

## External Access via Cloudflare Tunnel

Frigate is exposed through Cloudflare Tunnel configured in the Zero Trust dashboard:
- No ingress controller needed
- Automatic HTTPS with Cloudflare certificates
- Authentication handled by Frigate on port 8971

## Updating Configuration

To update Frigate configuration:

1. Edit `values-override.yaml`
2. Apply changes:
   ```bash
   kustomize build --enable-exec --enable-alpha-plugins k0s/frigate/ | kubectl apply -f -
   ```

## Uninstall

```bash
kubectl delete -k k0s/frigate/
```

## Troubleshooting

### Pod won't start
- Check logs: `kubectl logs -n frigate deployment/frigate`
- Check events: `kubectl get events -n frigate`
- Verify storage class exists: `kubectl get storageclass`

### Can't access via Cloudflare tunnel
- Verify tunnel is connected: Check Cloudflare Zero Trust dashboard
- Ensure route is configured for `https://frigate.frigate.svc.cluster.local:8971`
- Enable "No TLS Verify" in tunnel configuration for self-signed certificates
- Check cloudflared logs: `kubectl logs -n cloudflare deployment/cloudflared`

### Authentication issues
- Default credentials: username `admin`, password from logs
- To reset: set `reset_admin_password: true` and redeploy

### Performance issues on Raspberry Pi
- Reduce detection fps in camera config
- Use CPU detector instead of Coral
- Limit number of cameras
- Adjust resource limits in values-override.yaml

## Resources

- [Frigate Documentation](https://docs.frigate.video/)
- [Frigate Configuration](https://docs.frigate.video/configuration/)
- [Helm Chart Source](https://github.com/blakeblackshear/blakeshome-charts/tree/master/charts/frigate)