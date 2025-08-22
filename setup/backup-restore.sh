#!/bin/bash
set -e

# k0s Backup and Restore Script
# For disaster recovery and migration

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Create comprehensive backup
create_backup() {
    log_info "Creating comprehensive backup..."
    
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_DIR="backups/full_backup_$TIMESTAMP"
    mkdir -p "$BACKUP_DIR"
    
    # Backup local configuration
    log_info "Backing up local configuration..."
    cp cluster.yaml "$BACKUP_DIR/" 2>/dev/null || log_warn "cluster.yaml not found"
    cp kubeconfig.yaml "$BACKUP_DIR/" 2>/dev/null || log_warn "kubeconfig.yaml not found"
    cp pi5-k0s-setup.sh "$BACKUP_DIR/" 2>/dev/null || log_warn "Setup script not found"
    cp deploy.sh "$BACKUP_DIR/" 2>/dev/null || log_warn "Deploy script not found"
    
    # Backup k0s configuration from Pi
    log_info "Backing up k0s configuration from Raspberry Pi..."
    ssh -i ~/.ssh/momscloset alan@mctv3.local "sudo k0s backup --save-path /tmp/k0s-backup.tar.gz" 2>/dev/null || {
        log_warn "Could not create k0s backup on Pi"
    }
    
    # Download the backup
    scp -i ~/.ssh/momscloset alan@mctv3.local:/tmp/k0s-backup.tar.gz "$BACKUP_DIR/" 2>/dev/null || {
        log_warn "Could not download k0s backup"
    }
    
    # Get cluster state information
    if [ -f kubeconfig.yaml ]; then
        export KUBECONFIG=$(pwd)/kubeconfig.yaml
        
        if command -v kubectl &> /dev/null; then
            log_info "Backing up cluster state information..."
            kubectl get nodes -o yaml > "$BACKUP_DIR/nodes.yaml" 2>/dev/null || true
            kubectl get namespaces -o yaml > "$BACKUP_DIR/namespaces.yaml" 2>/dev/null || true
            kubectl get all --all-namespaces -o yaml > "$BACKUP_DIR/all-resources.yaml" 2>/dev/null || true
        fi
    fi
    
    # Document current state
    cat > "$BACKUP_DIR/backup-info.txt" << EOF
Backup created: $TIMESTAMP
Hostname: mctv3.local
User: alan
SSH Key: ~/.ssh/momscloset

Files included:
- cluster.yaml: k0sctl cluster configuration
- kubeconfig.yaml: Kubernetes access configuration
- k0s-backup.tar.gz: k0s system backup (if available)
- Setup and deployment scripts

To restore:
1. Ensure Raspberry Pi has fresh OS installation
2. Run restore script with this backup directory
EOF
    
    # Create tarball of backup
    log_info "Creating backup archive..."
    tar -czf "backups/k0s-backup-$TIMESTAMP.tar.gz" -C backups "full_backup_$TIMESTAMP"
    
    log_info "Backup completed: backups/k0s-backup-$TIMESTAMP.tar.gz"
    echo "Backup directory: $BACKUP_DIR"
}

# Restore from backup
restore_backup() {
    echo "Available backups:"
    ls -la backups/*.tar.gz 2>/dev/null || {
        log_error "No backups found"
        exit 1
    }
    
    echo ""
    echo "Enter backup filename to restore (or full path):"
    read -r BACKUP_FILE
    
    if [ ! -f "$BACKUP_FILE" ]; then
        if [ -f "backups/$BACKUP_FILE" ]; then
            BACKUP_FILE="backups/$BACKUP_FILE"
        else
            log_error "Backup file not found: $BACKUP_FILE"
            exit 1
        fi
    fi
    
    log_info "Extracting backup..."
    TEMP_DIR="/tmp/k0s-restore-$$"
    mkdir -p "$TEMP_DIR"
    tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR"
    
    # Find the backup directory
    BACKUP_DIR=$(find "$TEMP_DIR" -type d -name "full_backup_*" | head -1)
    
    if [ -z "$BACKUP_DIR" ]; then
        log_error "Invalid backup format"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    log_info "Restoring configuration files..."
    cp "$BACKUP_DIR"/*.yaml . 2>/dev/null || true
    cp "$BACKUP_DIR"/*.sh . 2>/dev/null || true
    
    echo ""
    log_warn "Restoration steps:"
    echo "1. Ensure Raspberry Pi has fresh OS with SSH enabled"
    echo "2. Run: ./deploy.sh (option 2) to setup SSH"
    echo "3. Run: ./deploy.sh (option 3) to prepare the Pi"
    echo "4. If k0s backup exists, restore it on the Pi:"
    echo "   scp -i ~/.ssh/momscloset $BACKUP_DIR/k0s-backup.tar.gz alan@mctv3.local:/tmp/"
    echo "   ssh -i ~/.ssh/momscloset alan@mctv3.local 'sudo k0s restore /tmp/k0s-backup.tar.gz'"
    echo "5. Run: ./deploy.sh (option 4) to deploy cluster"
    
    rm -rf "$TEMP_DIR"
    log_info "Configuration files restored to current directory"
}

# Document recovery procedure
create_recovery_docs() {
    log_info "Creating recovery documentation..."
    
    cat > RECOVERY.md << 'EOF'
# k0s Raspberry Pi 5 Recovery Guide

## Prerequisites
- Raspberry Pi 5 with fresh Raspberry Pi OS (64-bit)
- Backup files from this deployment
- Network connectivity

## Recovery Steps

### 1. Prepare Fresh Raspberry Pi OS
1. Flash Raspberry Pi OS to SD card using Raspberry Pi Imager
2. Enable SSH during setup
3. Set hostname to `mctv3`
4. Set username to `alan`
5. Boot the Raspberry Pi

### 2. Initial System Setup
From your workstation:
```bash
# Upload SSH key
ssh-copy-id -i ~/.ssh/momscloset.pub alan@mctv3.local

# Copy and run setup script
scp -i ~/.ssh/momscloset pi5-k0s-setup.sh alan@mctv3.local:/tmp/
ssh -i ~/.ssh/momscloset alan@mctv3.local "sudo bash /tmp/pi5-k0s-setup.sh"
```

The Pi will reboot after cgroup configuration.

### 3. Deploy k0s Cluster

#### Option A: Fresh Installation
```bash
./deploy.sh
# Select option 1 for full deployment
```

#### Option B: Restore from Backup
```bash
# Restore configuration
./backup-restore.sh
# Select option 2 (Restore)

# If k0s backup exists, restore it:
scp -i ~/.ssh/momscloset backups/[backup]/k0s-backup.tar.gz alan@mctv3.local:/tmp/
ssh -i ~/.ssh/momscloset alan@mctv3.local 'sudo k0s restore /tmp/k0s-backup.tar.gz'

# Deploy cluster
k0sctl apply --config cluster.yaml
```

### 4. Verify Recovery
```bash
export KUBECONFIG=$(pwd)/kubeconfig.yaml
kubectl get nodes
kubectl get pods -A
```

## Backup Schedule Recommendations
- Daily: Configuration files (automated via cron)
- Weekly: Full k0s backup
- Before major changes: Full backup

## Automation Setup
Add to crontab on workstation:
```bash
# Daily configuration backup at 2 AM
0 2 * * * cd /path/to/k0s && ./backup-restore.sh backup-config
```

## Troubleshooting

### SSH Connection Issues
- Verify Pi is on network: `ping mctv3.local`
- Check SSH service: `ssh alan@mctv3.local 'systemctl status ssh'`
- Verify key permissions: `chmod 600 ~/.ssh/momscloset`

### k0s Deployment Failures
- Check cgroups enabled: `ssh alan@mctv3.local 'cat /proc/cgroups'`
- Verify k0s installation: `ssh alan@mctv3.local 'k0s version'`
- Check logs: `ssh alan@mctv3.local 'sudo journalctl -u k0scontroller'`

### Cluster Access Issues
- Regenerate kubeconfig: `k0sctl kubeconfig --config cluster.yaml > kubeconfig.yaml`
- Check API server: `curl -k https://mctv3.local:6443`
EOF
    
    log_info "Recovery documentation created: RECOVERY.md"
}

# Quick configuration backup (for cron)
backup_config_only() {
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_DIR="backups/config_$TIMESTAMP"
    mkdir -p "$BACKUP_DIR"
    
    cp *.yaml "$BACKUP_DIR/" 2>/dev/null || true
    cp *.sh "$BACKUP_DIR/" 2>/dev/null || true
    
    # Keep only last 7 config backups
    ls -t backups/config_* 2>/dev/null | tail -n +8 | xargs rm -rf 2>/dev/null || true
    
    echo "Config backed up to $BACKUP_DIR"
}

# Main menu
show_menu() {
    echo ""
    echo "========================================="
    echo "k0s Backup and Restore Tool"
    echo "========================================="
    echo "1. Create full backup"
    echo "2. Restore from backup"
    echo "3. Create recovery documentation"
    echo "4. Quick config backup"
    echo "5. Exit"
    echo ""
    echo -n "Select an option: "
}

# Handle command line arguments for automation
if [ "$1" = "backup-config" ]; then
    backup_config_only
    exit 0
fi

# Main execution
main() {
    while true; do
        show_menu
        read -r option
        
        case $option in
            1)
                create_backup
                ;;
            2)
                restore_backup
                ;;
            3)
                create_recovery_docs
                ;;
            4)
                backup_config_only
                ;;
            5)
                exit 0
                ;;
            *)
                log_error "Invalid option"
                ;;
        esac
    done
}

main "$@"