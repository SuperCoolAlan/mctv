# Known Issues and Solutions

## During Initial Setup

### 1. SSH Key Not Found
**Issue**: `SSH key not found at ~/.ssh/momscloset`
**Solution**: Create or copy your SSH key to the correct location:
```bash
# Generate new key if needed
ssh-keygen -t rsa -b 4096 -f ~/.ssh/momscloset
```

### 2. Pi Not Accessible
**Issue**: `Cannot connect to alan@mctv3.local`
**Solution**: 
- Check Pi is on network: Try IP address instead of hostname
- Ensure SSH is enabled in Pi configuration
- Try: `ssh alan@<IP_ADDRESS>`

### 3. Cgroups Reboot
**Issue**: Pi reboots during setup
**Solution**: This is expected if cgroups weren't configured. Wait 2-3 minutes and continue.

## During k0s Deployment

### 4. k0sctl Not Found
**Issue**: `k0sctl is not installed`
**Solution**: 
```bash
brew install k0sctl
# or download from https://github.com/k0sproject/k0sctl/releases
```

### 5. Node Taint Not Removed
**Issue**: Pods stuck in Pending due to control-plane taint
**Solution**: The deploy.sh script should handle this, but if not:
```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

## During Application Deployment

### 6. SOPS/KSOPS Errors
**Issue**: `error decrypting secret`
**Solution**: Ensure GPG key is available:
```bash
gpg --list-keys 29FE211C0F0BF17C10EFEB150ECC79FC3C76B242
```

### 7. Kustomize Plugin Errors
**Issue**: `couldn't load plugin`
**Solution**: Use the correct flags:
```bash
kustomize build --enable-exec --enable-alpha-plugins . | kubectl apply -f -
```

## Service-Specific Issues

### 8. Cloudflare Tunnel "Unauthorized"
**Issue**: Tunnel shows authentication errors
**Solution**: Token may be incorrect or expired. Get new token from Cloudflare dashboard.

### 9. Frigate Won't Start
**Issue**: Frigate pod crashes or restarts
**Common Causes**:
- Insufficient memory (needs 1-2GB)
- Coral USB issues (disable Coral in values-override.yaml)
- Storage provisioning failed

### 10. Coral USB Disconnecting
**Issue**: `USB disconnect` in dmesg
**Solution**: 
- Power issue - use powered USB hub
- Check Edge TPU runtime is set to reduced frequency:
  ```bash
  dpkg -l | grep libedgetpu
  # Should show libedgetpu1-std, not libedgetpu1-max
  ```

### 11. Twingate Not Connecting
**Issue**: Connector shows "Offline"
**Solution**: Tokens may be expired. Generate new tokens in Twingate admin panel.

## Performance Issues

### 12. High CPU/Memory Usage
**Issue**: Node resources exhausted
**Solution**: 
- Reduce Frigate detection FPS
- Disable unused cameras
- Use CPU detector instead of Coral if needed
- Check resource limits in values-override.yaml files

### 13. Slow Storage
**Issue**: PVC provisioning slow or failing
**Solution**: Default local-path provisioner can be slow on SD cards. Consider:
- Using faster SD card (A2 rated)
- External SSD via USB 3.0
- Reducing retention periods

## Network Issues

### 14. Services Not Accessible
**Issue**: Can't reach services externally
**Solution**: 
- Check Cloudflare tunnel is healthy
- Verify DNS records in Cloudflare
- Ensure service URLs in tunnel config are correct
- Use full service DNS: `service.namespace.svc.cluster.local`

### 15. DNS Resolution Failures
**Issue**: Services can't resolve external domains
**Solution**: CoreDNS should handle this, but check:
```bash
kubectl get pods -n kube-system | grep coredns
kubectl logs -n kube-system deployment/coredns
```

## Recovery

### 16. Complete Failure
**Issue**: Cluster completely broken
**Solution**: 
1. Save any important data
2. Run `k0sctl reset --config cluster.yaml`
3. Start fresh with setup process
4. Restore from backups if available