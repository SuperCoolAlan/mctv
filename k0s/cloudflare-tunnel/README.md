# Cloudflare Tunnel for mctv Cluster

This deploys a Cloudflare Tunnel (cloudflared) to expose services from your k0s cluster to the internet securely without opening ports on your router.

## How It Works

Cloudflare Tunnel creates an outbound-only connection from your cluster to Cloudflare's edge network. This means:
- No need to open inbound ports on your firewall/router
- No need for a static IP address
- Automatic SSL/TLS certificates from Cloudflare
- DDoS protection and Cloudflare's security features

## Prerequisites

1. A Cloudflare account (free tier works)
2. A domain name using Cloudflare DNS
3. k0s cluster running (completed via setup scripts)
4. kubectl configured with kubeconfig

## Setup Instructions

### 1. Create a Cloudflare Tunnel

1. Log in to [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
2. Navigate to **Networks** > **Tunnels**
3. Click **Create a tunnel**
4. Choose **Cloudflared** as the connector type
5. Name your tunnel (e.g., `mctv-tunnel`)
6. Save the tunnel
7. **IMPORTANT**: Download and save the credentials JSON file

### 2. Configure the Tunnel with Token Authentication

1. In the Cloudflare Zero Trust Dashboard, after creating your tunnel:
   - Click on your tunnel name
   - Go to the **Configure** tab
   - Copy the **token** from the installation command

2. Create the token secret (already encrypted with SOPS):
   ```bash
   # The token is stored in secrets/tunnel-token-secret.enc.yaml
   # To view/edit the encrypted token:
   sops secrets/tunnel-token-secret.enc.yaml
   ```

3. Configure routes in Cloudflare Dashboard:
   - Click **Public Hostname** tab
   - Add your services (e.g., Frigate):
     - Subdomain: `momscloset` (or your choice)
     - Domain: `asandov.com`
     - Service: `https://frigate.frigate.svc.cluster.local:8971`
     - Additional settings: Enable "No TLS Verify"

**Note**: When using token authentication, all routing configuration is done in the Cloudflare dashboard, not in local config files.

### 4. Deploy

```bash
# Set kubeconfig - This deployment uses the mctv3 context
export KUBECONFIG=~/.kube/clusters/mctv3.yaml

# Deploy using kustomize with KSOPS for secret management
kustomize build --enable-exec --enable-alpha-plugins . | kubectl apply -f -

# Or preview first
kustomize build --enable-exec --enable-alpha-plugins .
```

**Note**: This deployment follows the secrets management practices defined in [homelab-manifests/CLAUDE.md](/Users/alan/Documents/homelab-manifests/CLAUDE.md) using SOPS encryption with KSOPS.

### 5. Configure DNS

After deployment, configure DNS in Cloudflare:

1. Go to your domain's DNS settings in Cloudflare
2. Add CNAME records pointing to your tunnel:
   ```
   frigate.yourdomain.com -> tunnel-id.cfargotunnel.com
   ```
   Or use the Cloudflare dashboard to configure routes

## Verify Deployment

```bash
# Check if pod is running
kubectl get pods -n cloudflare

# Check logs
kubectl logs -n cloudflare deployment/cloudflared

# Check if tunnel is connected
kubectl logs -n cloudflare deployment/cloudflared | grep "Connection registered"
```

## Routing Options

### Option 1: Direct Service Routing (Recommended for Simple Setup)
Route directly to services without an ingress controller:
```yaml
ingress:
  - hostname: "frigate.yourdomain.com"
    service: "http://frigate.frigate.svc.cluster.local:5000"
  - hostname: "app2.yourdomain.com"
    service: "http://app2.namespace.svc.cluster.local:8080"
```

### Option 2: Through Ingress Controller
If you have an ingress controller installed:
```yaml
ingress:
  - hostname: "*.yourdomain.com"
    service: "https://ingress-nginx-controller.ingress-nginx.svc.cluster.local:443"
    originRequest:
      noTLSVerify: true
```

## Adding More Services

To expose additional services:

1. Edit `values-override.yaml`
2. Add new hostname entries under `ingress:`
3. Apply changes:
   ```bash
   kubectl apply -k k0s/cloudflare-tunnel/
   ```

## Security Considerations

- **Never commit** `tunnel-credentials.yaml` to git
- Use Cloudflare Access policies for authentication if needed
- Consider using Cloudflare WAF rules for additional security
- The tunnel credentials provide full access to route traffic - keep them secure

## Troubleshooting

### Pod won't start
- Check credentials: `kubectl describe secret -n cloudflare tunnel-credentials`
- Check logs: `kubectl logs -n cloudflare deployment/cloudflared`

### Cannot access service
- Verify DNS records in Cloudflare
- Check tunnel status in Cloudflare dashboard
- Verify service is running: `kubectl get svc -A`
- Check cloudflared logs for connection errors

### Connection issues
- Ensure the Pi has internet connectivity
- Check if tunnel shows as "Healthy" in Cloudflare dashboard
- Verify the service URLs in values-override.yaml are correct

## Uninstall

```bash
kubectl delete -k k0s/cloudflare-tunnel/
kubectl delete secret -n cloudflare tunnel-credentials
```

## Resources

- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
- [Ingress Rules Configuration](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/configuration/configuration-file/ingress/)