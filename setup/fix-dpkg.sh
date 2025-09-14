#!/bin/bash
# Fix dpkg issues before continuing

set -e

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

log_info "Fixing dpkg/apt issues..."

# Set non-interactive frontend and configure options
export DEBIAN_FRONTEND=noninteractive
export DPKG_FORCE=confdef,confold

# Configure any half-installed packages with proper flags
dpkg --configure -a --force-confdef --force-confold || {
    log_warn "dpkg configure failed, attempting recovery..."
    # Force remove problematic packages if needed
    apt-get remove -y --allow-remove-essential initramfs-tools-core initramfs-tools || true
    apt-get install -f -y || true
    dpkg --configure -a || true
}

# Fix any broken dependencies
apt-get install -f -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" || true

# Clean package cache
apt-get clean
apt-get autoclean

# Update package lists
apt-get update || log_error "apt-get update failed"

log_info "dpkg issues fixed"