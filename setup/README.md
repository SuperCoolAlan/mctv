# k0s on Raspberry Pi 5 - Deployment Scripts

This repository contains scripts for deploying and managing k0s Kubernetes on a Raspberry Pi 5.

## Prerequisites

- Raspberry Pi 5 with 64-bit Raspberry Pi OS
- SSH access configured (user: `alan`, host: `mctv3.local`)
- SSH key at `~/.ssh/momscloset`
- k0sctl installed on your workstation ([installation guide](https://github.com/k0sproject/k0sctl#installation))

## Scripts Overview

### 1. `setup-remote.sh`
Prepares the Raspberry Pi for k0s installation by copying and executing the setup script remotely.
- Enables memory cgroups (required for k0s)
- Installs k0s binary
- Configures system settings
- **Note:** Pi will reboot after cgroup configuration

### 2. `wifi-config.sh` 
Configures WiFi connection for deployment network.
- Sets up connection to "momscloset" network
- Can configure remotely via SSH or generate config for SD card

### 3. `deploy.sh`
Main deployment tool with interactive menu.
- Sets up SSH authentication
- Deploys k0s cluster using k0sctl
- Retrieves kubeconfig
- Verifies cluster health

### 4. `validate.sh`
Comprehensive health checking tool.
- Checks system resources
- Validates k0s installation
- Verifies cluster components
- Tests network connectivity
- Monitors performance

### 5. `backup-restore.sh`
Backup and disaster recovery tool.
- Creates full backups of configuration and cluster state
- Provides restoration procedures
- Generates recovery documentation

### 6. `setup-coral-usb.sh`
Prepares the system for Google Coral USB TPU support.
- Installs udev rules for proper device permissions
- Configures USB access for containers
- Verifies Coral device detection
- **Note:** Run this before deploying Frigate if using Coral for object detection

## Quick Start

### Initial Setup

1. **Configure WiFi (if needed):**
   ```bash
   ./wifi-config.sh
   # Select option 1 to configure remotely
   ```

2. **Prepare the Raspberry Pi:**
   ```bash
   ./setup-remote.sh
   ```
   Wait for reboot if cgroups were configured.

3. **Deploy k0s cluster:**
   ```bash
   ./deploy.sh
   # Select option 1 for full deployment
   ```

4. **Access your cluster:**
   ```bash
   export KUBECONFIG=$(pwd)/kubeconfig.yaml
   kubectl get nodes
   ```

## Step-by-Step Deployment

### Step 1: SSH Key Setup
Ensure your SSH key is uploaded to the Pi:
```bash
ssh-copy-id -i ~/.ssh/momscloset.pub alan@mctv3.local
```

### Step 2: System Preparation
Run the setup script to prepare the Pi:
```bash
./setup-remote.sh
```
This will:
- Enable memory cgroups
- Install k0s
- Configure kernel modules
- Set up IP forwarding

**Important:** The Pi will need to reboot for cgroup changes.

### Step 3: Cluster Deployment
After the Pi has rebooted:
```bash
./deploy.sh
```
Choose option 1 for full deployment, or use individual options for specific tasks.

### Step 4: Validation
Verify your cluster is healthy:
```bash
./validate.sh
# Select option 1 for full validation
```

### Step 5: Backup
Create a backup of your deployment:
```bash
./backup-restore.sh
# Select option 1 to create full backup
```

## Configuration Files

### `cluster.yaml`
k0sctl cluster configuration file. Defines:
- Node configuration (controller+worker mode)
- Network settings (Calico CNI)
- API server configuration
- k0s version

**Important:** This configuration uses dynamic IP addressing. The cluster will automatically use whatever IP is assigned by DHCP. Do not hardcode IP addresses in this file.

Edit this file to customize your deployment.

### Note on `cluster-ip.yaml`
If you see a `cluster-ip.yaml` file, this is an outdated configuration with hardcoded IPs. Do not use it. Always use `cluster.yaml` which supports dynamic IPs.

## Recovery Procedures

If you need to recover from a failure:

1. **Fresh Pi Installation:**
   - Flash new Raspberry Pi OS
   - Set hostname to `mctv3`
   - Enable SSH

2. **Restore from Backup:**
   ```bash
   ./backup-restore.sh
   # Select option 2 (Restore)
   # Follow the prompts
   ```

3. **Redeploy:**
   ```bash
   ./deploy.sh
   ```

## Maintenance

### Daily Tasks
- Check cluster health: `./validate.sh` (option 2 - quick check)

### Weekly Tasks
- Full validation: `./validate.sh` (option 1)
- Create backup: `./backup-restore.sh` (option 1)

### Before Changes
- Always create a backup before making cluster changes
- Validate cluster health after changes

## Troubleshooting

### SSH Connection Issues
```bash
# Test connection
ssh -i ~/.ssh/momscloset alan@mctv3.local echo "connected"

# Check if Pi is on network
ping mctv3.local
```

### k0s Not Starting
```bash
# Check logs on Pi
ssh -i ~/.ssh/momscloset alan@mctv3.local "sudo journalctl -u k0scontroller -f"

# Verify cgroups enabled
ssh -i ~/.ssh/momscloset alan@mctv3.local "cat /proc/cgroups"
```

### Cluster Access Issues
```bash
# Regenerate kubeconfig
k0sctl kubeconfig --config cluster.yaml > kubeconfig.yaml

# Test API server
curl -k https://mctv3.local:6443
```

## Security Notes

1. **WiFi Credentials:** The `wifi-config.sh` file contains WiFi passwords. Never commit this to version control.

2. **SSH Keys:** Ensure your SSH private key (`~/.ssh/momscloset`) has proper permissions:
   ```bash
   chmod 600 ~/.ssh/momscloset
   ```

3. **Backups:** Store backups securely, they contain sensitive cluster information.

## Additional Resources

- [k0s Documentation](https://docs.k0sproject.io/)
- [k0s on Raspberry Pi Guide](https://docs.k0sproject.io/stable/raspberry-pi5/)
- [k0sctl Documentation](https://github.com/k0sproject/k0sctl)

## Support

For issues or questions:
- Check the validation script for diagnostics: `./validate.sh`
- Review logs on the Pi: `ssh alan@mctv3.local "sudo k0s status"`
- Consult the recovery documentation: `RECOVERY.md` (generated by backup-restore.sh)
