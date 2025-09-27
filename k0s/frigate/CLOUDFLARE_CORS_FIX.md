# Cloudflare CORS Fix for Frigate

This directory includes an nginx proxy that sits between the Cloudflare tunnel and Frigate to handle CORS issues with Cloudflare's analytics scripts.

## How it works

1. The nginx proxy intercepts all HTML responses from Frigate
2. It removes problematic Cloudflare analytics scripts that cause CORS/integrity errors
3. It properly sets CSP headers to allow the remaining scripts

## Components

- `nginx-proxy-configmap.yaml` - Nginx configuration that filters out Cloudflare scripts
- `nginx-proxy-deployment.yaml` - Deployment and service for the nginx proxy

## Cloudflare Dashboard Configuration

Since your tunnel uses token-based configuration, you need to update the service URL in the Cloudflare dashboard:

1. Go to **Cloudflare Zero Trust** → **Access** → **Tunnels**
2. Click on your tunnel
3. Go to the **Public Hostname** tab
4. Find the entry for `momscloset.asandov.com`
5. Change the service from:
   - `https://frigate.frigate.svc.cluster.local:8971`

   To:
   - `http://frigate-nginx-proxy.frigate.svc.cluster.local:8080`

6. Save the changes

## Alternative Solutions

If you prefer, you can modify the nginx config to keep Cloudflare analytics:

1. Edit `nginx-proxy-configmap.yaml`
2. Comment out the line that removes scripts entirely
3. Uncomment the lines that remove only the integrity attributes
4. Redeploy with `kustomize build --enable-exec --enable-alpha-plugins . | kubectl apply -f -`