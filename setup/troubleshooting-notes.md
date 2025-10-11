# Troubleshooting Notes - mctv3 Node Setup

## Current Status (2025-09-18)
- Node successfully moved from ethernet to WiFi (momscloset hotspot)
- k0s cluster v1.33.4 installed and running
- Twingate connector pod is connecting to cloud server
- SSH/kubectl access through Twingate not working yet
- Services (Cloudflare Tunnel, Frigate, Twingate) not yet deployed

## Issues to Investigate

### 1. Twingate Connectivity
- SSH connection closes immediately when connecting to 100.107.187.121
- Need to verify Twingate connector status on the Pi
- Check if firewall rules need adjustment for WiFi interface
- Verify NetworkManager isn't interfering with Twingate routing

### 2. Service Deployment Status
- Services haven't been deployed yet (Cloudflare Tunnel, Frigate, Twingate)
- Need to deploy once we regain cluster access
- Deployment order: Cloudflare Tunnel → Frigate → Twingate

### 3. Kubeconfig Update Required
- Current kubeconfig points to old ethernet IP (10.0.1.16)
- Need to update with new IP once Twingate connection works
- May need to use node's WiFi IP directly if Twingate issues persist

### 4. Cloudflare Tunnel Investigation
- Once deployed, verify tunnel pod is running
- Check tunnel credentials and configuration
- Verify DNS records point to tunnel
- Check ingress rules for Frigate service

### 5. Frigate Service Checks
- Verify Frigate deployment and pods are running
- Check PVC for recordings storage
- Verify Coral USB passthrough if using TPU
- Check service and ingress configuration

## Network Switching Issues - RESOLVED (2025-09-18)

### Problem: k0s Failed After WiFi Switch
When moving from ethernet to WiFi, k0s failed to start with "etcd connection refused" errors.

### Root Causes Identified:
1. **Hardcoded IP in SANs list**: k0s config had `10.0.1.16` hardcoded in the certificate SANs
2. **etcd peerAddress**: Was set to the old ethernet IP instead of a dynamic value
3. **kubelet node-ip**: Service file had `--node-ip=10.0.1.16` hardcoded

### Solution Applied:
Created `ensure-dynamic-ip.sh` script that:
- Removes hardcoded IPs from SANs list (keeping only localhost and hostnames)
- Sets etcd peerAddress to `0.0.0.0` (bind to all interfaces)
- Removes `--node-ip` flag from systemd service

### Key Learning:
etcd requires an IP address for its `listen-peer-urls`, not a hostname. Using `0.0.0.0` allows it to bind to any available interface, making the cluster network-agnostic.

## Next Steps
1. Always run `ensure-dynamic-ip.sh` after initial k0s deployment
2. Test cluster failover between ethernet/WiFi to verify fix
3. Document in main setup procedures
4. Consider adding this fix to k0sctl deployment process