# Cloudflare Tunnel and Frigate Integration

## How It Works

The integration between Cloudflare Tunnel and Frigate is direct and simple:

```
Internet → Cloudflare Edge → Cloudflare Tunnel (in cluster) → Frigate Service
```

No Kubernetes Ingress controller is needed!

## Architecture

1. **Cloudflare Tunnel** (cloudflared) runs as a pod in your cluster
2. It establishes outbound connections to Cloudflare's edge network
3. Traffic routes directly to services using internal Kubernetes DNS

## Configuring the Route

Since you're using the token-based tunnel, you need to configure routes in the Cloudflare Zero Trust dashboard:

1. Go to [Cloudflare Zero Trust](https://one.dash.cloudflare.com/)
2. Navigate to **Networks** → **Tunnels**
3. Find your tunnel (connected status should show green)
4. Click **Configure** → **Public Hostname**
5. Add a public hostname:
   - **Subdomain**: `momscloset`
   - **Domain**: `asandov.com`
   - **Type**: `HTTPS`
   - **URL**: `frigate.frigate.svc.cluster.local:8971`
   - **Additional Settings**: Enable "No TLS Verify"

## Service Discovery

Cloudflare Tunnel uses Kubernetes internal DNS to find services:

- **Pattern**: `<service-name>.<namespace>.svc.cluster.local:<port>`
- **Frigate**: `frigate.frigate.svc.cluster.local:5000`
- **Other services**: Follow the same pattern

## Adding More Services

To expose additional services through the tunnel:

1. Deploy your service (no ingress needed)
2. Note the service name, namespace, and port
3. Add a new public hostname in Cloudflare dashboard
4. Point it to: `<service>.<namespace>.svc.cluster.local:<port>`

## Example Services

```yaml
# Frigate NVR (with authentication)
momscloset.asandov.com → frigate.frigate.svc.cluster.local:8971

# Home Assistant (if you add it)
ha.asandov.com → home-assistant.default.svc.cluster.local:8123

# Grafana (if you add it)
grafana.asandov.com → grafana.monitoring.svc.cluster.local:3000
```

## Advantages

1. **No Ingress Controller** - Saves resources on Raspberry Pi
2. **No Port Forwarding** - No firewall configuration needed
3. **Automatic TLS** - Cloudflare provides SSL certificates
4. **DDoS Protection** - Built-in Cloudflare protection
5. **Simple Configuration** - Just service names, no ingress rules

## Security Options

In Cloudflare Zero Trust dashboard, you can add:

- **Access Policies** - Require authentication
- **WAF Rules** - Web application firewall
- **Rate Limiting** - Prevent abuse
- **Country Restrictions** - Geo-blocking

## Troubleshooting

### Can't access Frigate

1. Check tunnel is connected:
   ```bash
   kubectl logs -n cloudflare deployment/cloudflared
   ```

2. Verify Frigate service exists:
   ```bash
   kubectl get svc -n frigate
   ```

3. Test internal connectivity:
   ```bash
   kubectl run test --rm -it --image=busybox --restart=Never -- wget -O- http://frigate.frigate.svc.cluster.local:5000
   ```
   Note: Port 5000 is unauthenticated; port 8971 requires HTTPS and auth

4. Check Cloudflare dashboard:
   - Tunnel shows as "Healthy"
   - Public hostname is configured correctly
   - DNS records are set up

### WebSocket Issues

Frigate uses WebSockets for live view. Cloudflare Tunnel handles this automatically, but ensure:
- Your Cloudflare plan supports WebSockets (all plans do)
- No proxy/firewall is blocking WebSocket connections on client side

## Deploy Order

1. Deploy Frigate:
   ```bash
   kubectl apply -k k0s/frigate/
   ```

2. Verify service is running:
   ```bash
   kubectl get svc -n frigate
   ```

3. Configure route in Cloudflare dashboard

4. Access via: `https://momscloset.asandov.com`