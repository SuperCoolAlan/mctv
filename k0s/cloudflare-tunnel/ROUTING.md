# Cloudflare Tunnel Routing Configuration

This Cloudflare tunnel deployment uses **token-based authentication**. All routing configuration is managed through the Cloudflare Zero Trust dashboard, not local config files.

## Current Routes

| Hostname | Service | Port | Description |
|----------|---------|------|-------------|
| momscloset.asandov.com | frigate.frigate.svc.cluster.local | 8971 | Frigate NVR (HTTPS with authentication) |

## Managing Routes

Since this deployment uses token authentication, routes must be configured in the Cloudflare dashboard:

1. Go to [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
2. Navigate to **Networks** → **Tunnels**
3. Click on your tunnel (ID: `03b29dbf-664a-451f-9f51-33980b1366f9`)
4. Click **Configure** → **Public Hostname** tab
5. Add or modify routes as needed

## Adding New Services

To expose a new service through the Cloudflare tunnel:

1. In the Cloudflare dashboard, add a new public hostname:
   - **Subdomain**: `yourservice`
   - **Domain**: `asandov.com`
   - **Service Type**: `HTTP` or `HTTPS`
   - **URL**: `service-name.namespace.svc.cluster.local:port`
   
2. For HTTPS services with self-signed certificates:
   - Enable **No TLS Verify** in Additional Settings

3. The changes take effect immediately - no pod restart needed

## Service Naming Convention

Kubernetes services are accessed using internal DNS:
- Pattern: `<service-name>.<namespace>.svc.cluster.local:<port>`
- Examples:
  - Frigate: `frigate.frigate.svc.cluster.local:8971`
  - Twingate: `twingate-connector.twingate.svc.cluster.local:8080`

## Port Selection

Choose the appropriate port based on your security needs:
- **Unauthenticated ports**: For services with their own auth or internal-only access
- **Authenticated ports**: For services requiring login (like Frigate on 8971)

## Security Notes

- The tunnel token contains all configuration and credentials
- Routes configured in the dashboard are immediately active
- Consider using Cloudflare Access for additional security layers
- For HTTPS services, enable "No TLS Verify" to handle self-signed certificates

## Troubleshooting

### Service not accessible
1. Verify the tunnel is connected in the dashboard
2. Check the service exists and is running:
   ```bash
   kubectl get svc -n <namespace>
   ```
3. Test internal connectivity from cloudflared pod
4. Check cloudflared logs for connection errors:
   ```bash
   kubectl logs -n cloudflare deployment/cloudflared
   ```