# Fresh Install Checklist

## Pre-Setup (on workstation)

- [ ] Install required tools:
  ```bash
  brew install k0sctl kubectl kustomize
  ```
- [ ] SSH key exists at `~/.ssh/momscloset` and `~/.ssh/momscloset.pub`
- [ ] Clone this repository to your workstation
- [ ] Have GPG key for SOPS (ID: `29FE211C0F0BF17C10EFEB150ECC79FC3C76B242`)

## Raspberry Pi Preparation

- [ ] Flash Raspberry Pi OS Lite 64-bit (Bookworm) 
- [ ] Configure in Pi Imager:
  - [ ] Hostname: `mctv3`
  - [ ] Username: `alan`
  - [ ] Enable SSH
  - [ ] Set WiFi credentials (if using WiFi)
- [ ] Insert SD card and boot Pi
- [ ] Verify Pi is accessible: `ping mctv3.local`

## Initial Setup

- [ ] Run from `setup/` directory:
  ```bash
  ./setup-remote.sh
  ```
- [ ] Wait for automatic reboot (if cgroups needed configuration)
- [ ] Verify Pi is back online after reboot

## k0s Deployment

- [ ] Run deployment script:
  ```bash
  ./deploy.sh
  ```
- [ ] Select option 1 (Full deployment)
- [ ] Save kubeconfig to `~/.kube/clusters/mctv3.yaml`
- [ ] Verify cluster:
  ```bash
  export KUBECONFIG=~/.kube/clusters/mctv3.yaml
  kubectl get nodes
  ```

## Optional: Coral USB Setup

- [ ] SSH into Pi:
  ```bash
  ssh -i ~/.ssh/momscloset alan@mctv3.local
  ```
- [ ] Run Coral setup:
  ```bash
  sudo bash /home/alan/setup-coral-usb.sh
  ```
- [ ] Verify Coral detected (after plugging in):
  ```bash
  lsusb | grep -E "(Google|18d1)"
  ```
- [ ] Exit SSH session

## Deploy Applications

- [ ] Set kubeconfig:
  ```bash
  export KUBECONFIG=~/.kube/clusters/mctv3.yaml
  ```

### 1. Cloudflare Tunnel
- [ ] Deploy:
  ```bash
  cd k0s/cloudflare-tunnel/
  kustomize build --enable-exec --enable-alpha-plugins . | kubectl apply -f -
  ```
- [ ] Verify pod running:
  ```bash
  kubectl get pods -n cloudflare
  ```
- [ ] Check logs show "Connection registered"

### 2. Frigate
- [ ] Deploy:
  ```bash
  cd k0s/frigate/
  kustomize build --enable-exec --enable-alpha-plugins . | kubectl apply -f -
  ```
- [ ] Get admin password:
  ```bash
  kubectl logs -n frigate deployment/frigate | grep "Password:"
  ```
- [ ] Save password to password manager

### 3. Twingate (if needed)
- [ ] Deploy:
  ```bash
  cd k0s/twingate/
  kustomize build --enable-exec --enable-alpha-plugins . | kubectl apply -f -
  ```
- [ ] Verify connector is "Online" in logs

## Configure External Access

- [ ] Go to [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
- [ ] Navigate to Networks → Tunnels
- [ ] Find your tunnel (should show "Healthy")
- [ ] Click Configure → Public Hostname
- [ ] Add hostname:
  - [ ] Subdomain: `momscloset`
  - [ ] Domain: `asandov.com`
  - [ ] Service: `https://frigate.frigate.svc.cluster.local:8971`
  - [ ] Enable "No TLS Verify" in Additional Settings
- [ ] Save configuration

## Verification

- [ ] All pods running:
  ```bash
  kubectl get pods -A | grep -v Running
  ```
- [ ] Access Frigate at https://momscloset.asandov.com
- [ ] Login with admin/password from earlier
- [ ] Cloudflare tunnel shows "Healthy" in dashboard
- [ ] (Optional) Twingate connector shows "Online"

## Post-Setup

- [ ] Update Frigate password via web UI
- [ ] Configure cameras in Frigate
- [ ] Set up Cloudflare Access policies if desired
- [ ] Document any custom configurations

## Troubleshooting Commands

If issues arise:
```bash
# Check all pods
kubectl get pods -A

# Check specific logs
kubectl logs -n cloudflare deployment/cloudflared
kubectl logs -n frigate deployment/frigate
kubectl logs -n twingate deployment/mctv3-connector

# Check events
kubectl get events -A --sort-by='.lastTimestamp'

# Check node resources
kubectl top nodes
```