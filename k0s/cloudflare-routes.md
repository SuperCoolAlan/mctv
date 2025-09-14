# Cloudflare Tunnel Routes for momscloset.asandov.com

## Domain Setup

Frigate will be accessible at the root domain:
- `momscloset.asandov.com` - Frigate NVR (main interface)

## Configure in Cloudflare Dashboard

1. Go to [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
2. Navigate to **Networks** → **Tunnels**
3. Click on your tunnel (should show as "Healthy")
4. Click **Configure** → **Public Hostname** tab
5. Click **Add a public hostname**

### Main Route: Frigate NVR on Root Domain

Configure the hostname:
- **Subdomain**: `momscloset`
- **Domain**: `asandov.com`
- **Path**: (leave empty)
- **Type**: `HTTPS`
- **URL**: `frigate.frigate.svc.cluster.local:8971`

Advanced options (required for HTTPS):
- **HTTP Host Header**: (leave as is)
- **Origin Server Name**: (leave as is)
- **No TLS Verify**: **Enable this** (required for self-signed certificates)

## DNS Configuration

The tunnel should automatically create the necessary DNS records. Verify in your Cloudflare DNS:

1. Go to your domain in Cloudflare dashboard
2. Click on **DNS** → **Records**
3. You should see CNAME records:
   - `momscloset` → `<tunnel-id>.cfargotunnel.com`

If not automatically created, add manually:
- **Type**: `CNAME`
- **Name**: `momscloset`
- **Target**: `<your-tunnel-id>.cfargotunnel.com`
- **Proxy status**: Proxied (orange cloud ON)

## Future Services

As you add more services, follow this pattern:

```
service.momscloset.asandov.com → service.namespace.svc.cluster.local:port
```

Examples:
- `ha.momscloset.asandov.com` → Home Assistant
- `grafana.momscloset.asandov.com` → Monitoring
- `pihole.momscloset.asandov.com` → Pi-hole admin

## Security Recommendations

For home security cameras, consider adding Cloudflare Access:

1. In Zero Trust dashboard, go to **Access** → **Applications**
2. Add an application for `momscloset.asandov.com`
3. Set up authentication (options):
   - Email OTP (one-time password)
   - Google/GitHub OAuth
   - Or create a bypass for your home IP

This adds an extra layer of security before anyone can access your camera feeds.

## Testing

Once configured, test access:

```bash
# From outside your network
curl -I https://momscloset.asandov.com

# Should return HTTP 200 or Frigate's login page
```

## Troubleshooting

If you can't access the site:

1. Check tunnel health in Cloudflare dashboard
2. Verify DNS propagation:
   ```bash
   nslookup momscloset.asandov.com
   ```
3. Check tunnel logs:
   ```bash
   export KUBECONFIG=~/.kube/clusters/mctv3.yaml
   kubectl logs -n cloudflare deployment/cloudflared
   ```
4. Ensure Frigate is running:
   ```bash
   kubectl get pods -n frigate
   ```