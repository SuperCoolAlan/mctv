#!/bin/bash
# Script to migrate k0s data to NVMe storage
# This should be run after stopping k0s

set -e

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
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

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run this script with sudo"
    exit 1
fi

log_info "Migrating k0s to NVMe storage..."

# Check if NVMe is mounted
if ! mount | grep -q "/mnt/nvme"; then
    log_error "NVMe not mounted at /mnt/nvme"
    exit 1
fi

# Stop k0s
log_info "Stopping k0s service..."
systemctl stop k0scontroller || true
sleep 5

# Wait for kubelet to fully stop
log_info "Waiting for kubelet to stop..."
while pgrep -x kubelet > /dev/null; do
    sleep 2
done

# Check if k0s directory exists and is not a symlink
if [ -d /var/lib/k0s ] && [ ! -L /var/lib/k0s ]; then
    log_info "Moving k0s data to NVMe..."

    # Create backup directory name with timestamp
    BACKUP_DIR="/mnt/nvme/k0s-backup-$(date +%Y%m%d_%H%M%S)"

    # If k0s directory already exists on NVMe, back it up
    if [ -d /mnt/nvme/k0s ]; then
        log_warn "Backing up existing k0s directory on NVMe to $BACKUP_DIR"
        mv /mnt/nvme/k0s "$BACKUP_DIR"
    fi

    # Copy data to NVMe (using cp to preserve all attributes)
    log_info "Copying k0s data to NVMe (this may take a while)..."
    cp -a /var/lib/k0s /mnt/nvme/

    # Remove old directory and create symlink
    log_info "Creating symlink..."
    rm -rf /var/lib/k0s
    ln -s /mnt/nvme/k0s /var/lib/k0s

    log_info "k0s data successfully migrated to NVMe"
else
    if [ -L /var/lib/k0s ]; then
        log_info "k0s is already using NVMe storage"
    else
        log_error "/var/lib/k0s not found"
    fi
fi

# Handle containerd if it exists
if [ -d /var/lib/containerd ] && [ ! -L /var/lib/containerd ]; then
    log_info "Moving containerd data to NVMe..."

    # Create directory on NVMe if it doesn't exist
    mkdir -p /mnt/nvme/containerd

    # Copy data
    cp -a /var/lib/containerd/* /mnt/nvme/containerd/ 2>/dev/null || true

    # Remove old directory and create symlink
    rm -rf /var/lib/containerd
    ln -s /mnt/nvme/containerd /var/lib/containerd

    log_info "containerd data migrated to NVMe"
fi

# Set proper permissions
log_info "Setting permissions..."
chown -R root:root /mnt/nvme/k0s
[ -d /mnt/nvme/containerd ] && chown -R root:root /mnt/nvme/containerd

# Start k0s again
log_info "Starting k0s service..."
systemctl start k0scontroller

log_info "Migration complete! k0s is now using NVMe storage."
log_info "Checking k0s status..."
sleep 5
systemctl status k0scontroller --no-pager || true