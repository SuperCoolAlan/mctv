# Cloudflare Tunnel Routing Configuration

This Cloudflare tunnel deployment provides external access to services running in the k0s cluster.

## Current Routes

| Hostname | Service | Port | Description |
|----------|---------|------|-------------|
| momscloset.asandov.com | frigate.frigate.svc.cluster.local | 8971 | Frigate NVR (authenticated) |

## Adding New Routes

To expose a new service through the Cloudflare tunnel:

1. Edit `tunnel-config.yaml`
2. Add a new ingress rule before the catch-all rule:
   ```yaml
   - hostname: yourservice.asandov.com
     service: http://service-name.namespace.svc.cluster.local:port
     originRequest:
       connectTimeout: 30s
       tcpKeepAlive: 30s
       keepAliveTimeout: 90s
   ```
3. Apply the changes:
   ```bash
   kustomize build --enable-exec --enable-alpha-plugins . | kubectl apply -f -
   ```
4. Restart the cloudflared deployment:
   ```bash
   kubectl rollout restart deployment/cloudflared -n cloudflare
   ```

## DNS Configuration

Ensure your domain has a CNAME record pointing to your tunnel:
- Record: `yourservice` (or `@` for root domain)
- Target: `<tunnel-id>.cfargotunnel.com`
- Proxy status: Proxied (orange cloud ON)

## Security Notes

- Services exposed on authenticated ports (like Frigate on 8971) will require login
- Consider using Cloudflare Access for additional security layers
- For internal-only services, use port 5000 or similar unauthenticated ports