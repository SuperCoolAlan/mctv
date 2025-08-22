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
- `helm/frigate/` - Local copy of the Frigate Helm chart

## Configuration

### 1. Update Ingress Settings

Edit `values-override.yaml` to configure your ingress:

```yaml
ingress:
  hosts:
    - host: frigate.mctv3.local  # Change to your domain
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
kubectl apply -k k0s/frigate/

# Or use kustomize directly
kustomize build k0s/frigate/ | kubectl apply -f -
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

If ingress is configured:
- http://frigate.mctv3.local (or your configured hostname)

For local testing without ingress:
```bash
kubectl port-forward -n frigate svc/frigate 5000:5000
# Access at http://localhost:5000
```

## Installing Ingress Controller (if needed)

If you don't have an ingress controller installed:

```bash
# Install NGINX Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/baremetal/deploy.yaml

# Wait for it to be ready
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

## Updating Configuration

To update Frigate configuration:

1. Edit `values-override.yaml`
2. Apply changes:
   ```bash
   kubectl apply -k k0s/frigate/
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

### Can't access via ingress
- Verify ingress controller is running: `kubectl get pods -n ingress-nginx`
- Check ingress resource: `kubectl describe ingress -n frigate`
- Add hostname to /etc/hosts: `echo "10.0.1.16 frigate.mctv3.local" | sudo tee -a /etc/hosts`

### Performance issues on Raspberry Pi
- Reduce detection fps in camera config
- Use CPU detector instead of Coral
- Limit number of cameras
- Adjust resource limits in values-override.yaml

## Resources

- [Frigate Documentation](https://docs.frigate.video/)
- [Frigate Configuration](https://docs.frigate.video/configuration/)
- [Helm Chart Source](https://github.com/blakeblackshear/blakeshome-charts/tree/master/charts/frigate)