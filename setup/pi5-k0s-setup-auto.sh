#!/bin/bash
set -e

# Raspberry Pi 5 k0s Setup Script - Non-interactive version
# Based on: https://docs.k0sproject.io/stable/raspberry-pi5/

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

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
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run this script with sudo"
        exit 1
    fi
}

# Enable memory cgroups (required for k0s)
enable_cgroups() {
    log_info "Configuring memory cgroups..."

    # Try both possible locations for cmdline.txt
    CMDLINE_FILE="/boot/firmware/cmdline.txt"
    if [ ! -f "$CMDLINE_FILE" ]; then
        CMDLINE_FILE="/boot/cmdline.txt"
    fi

    if [ ! -f "$CMDLINE_FILE" ]; then
        log_error "Could not find cmdline.txt in /boot/firmware/ or /boot/"
        exit 1
    fi

    # Backup original file
    cp "$CMDLINE_FILE" "${CMDLINE_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

    # Check if all required cgroup settings exist
    if grep -q "cgroup_enable=cpuset" "$CMDLINE_FILE" && grep -q "cgroup_enable=memory" "$CMDLINE_FILE" && grep -q "cgroup_memory=1" "$CMDLINE_FILE"; then
        log_info "All required cgroups already enabled"
        # Check if cgroups are actually active in the current boot
        if [ -d "/sys/fs/cgroup/memory" ] && [ -f "/sys/fs/cgroup/memory/memory.limit_in_bytes" ]; then
            log_info "Memory cgroups are active"
            return 0
        else
            log_warn "Cgroups are configured but not active. Reboot required."
            NEEDS_REBOOT=true
            return 0
        fi
    else
        log_info "Adding cgroup configuration to $CMDLINE_FILE"
        # Remove any existing partial cgroup settings first
        sed -i 's/ cgroup_enable=cpuset//g; s/ cgroup_enable=memory//g; s/ cgroup_memory=1//g' "$CMDLINE_FILE"
        # Append all required cgroup settings to the existing line (cmdline.txt must be a single line)
        sed -i 's/$/ cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1/' "$CMDLINE_FILE"

        log_warn "Cgroup configuration added. System MUST be rebooted for changes to take effect."
        NEEDS_REBOOT=true
    fi
}

# Install k0s using the official script
install_k0s() {
    log_info "Installing k0s..."

    if command -v k0s &> /dev/null; then
        CURRENT_VERSION=$(k0s version)
        log_info "k0s is already installed. Version: $CURRENT_VERSION"
        log_info "Reinstalling/updating k0s..."
    fi

    log_info "Downloading and installing k0s using official script..."
    curl --proto '=https' --tlsv1.2 -sSf https://get.k0s.sh | sh

    if command -v k0s &> /dev/null; then
        log_info "k0s installed successfully. Version: $(k0s version)"
    else
        log_error "k0s installation failed"
        exit 1
    fi
}

# Configure system settings for k0s
configure_system() {
    log_info "Configuring system settings for k0s..."

    # Fix system time first
    log_info "Syncing system time..."
    systemctl stop systemd-timesyncd
    systemctl start systemd-timesyncd
    # Force time sync
    timedatectl set-ntp true
    # Wait a moment for time sync
    sleep 3
    log_info "Current time: $(date)"

    # Fix any potential dpkg issues first
    log_info "Checking and fixing any package manager issues..."
    export DEBIAN_FRONTEND=noninteractive

    # Configure any half-installed packages
    dpkg --configure -a || {
        log_warn "dpkg --configure -a failed, attempting to fix..."
        apt-get install -f -y || true
    }

    # Clean package cache
    apt-get clean
    apt-get autoclean

    # Update package lists
    apt-get update || {
        log_error "apt-get update failed"
        exit 1
    }

    # Update system with proper error handling
    log_info "Updating system packages..."
    apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" || {
        log_warn "Initial upgrade failed, attempting to fix and retry..."
        apt-get install -f -y
        dpkg --configure -a
        apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" || {
            log_error "System upgrade failed after retry"
            exit 1
        }
    }

    # Install useful tools
    log_info "Installing useful tools..."
    apt-get install -y \
        curl \
        wget \
        vim \
        htop \
        net-tools \
        iptables \
        arptables \
        ebtables || {
        log_warn "Some tools failed to install, attempting to fix..."
        apt-get install -f -y
        dpkg --configure -a
        # Try again with individual packages to identify any problematic ones
        for pkg in curl wget vim htop net-tools iptables arptables ebtables; do
            apt-get install -y $pkg || log_warn "Failed to install $pkg"
        done
    }

    # Enable IP forwarding
    log_info "Enabling IP forwarding..."
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/99-k0s.conf
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.d/99-k0s.conf
    sysctl -p /etc/sysctl.d/99-k0s.conf

    # Load required kernel modules
    log_info "Loading required kernel modules..."
    modprobe br_netfilter
    modprobe overlay

    # Make modules persistent
    echo "br_netfilter" >> /etc/modules-load.d/k0s.conf
    echo "overlay" >> /etc/modules-load.d/k0s.conf
}

# Main execution
main() {
    echo "========================================="
    echo "Raspberry Pi 5 k0s Setup Script (Auto)"
    echo "========================================="
    echo ""
    log_info "Running in non-interactive mode"

    check_root
    enable_cgroups
    configure_system
    install_k0s

    echo ""
    log_info "========================================="
    log_info "Raspberry Pi 5 k0s Setup Complete!"
    log_info "========================================="
    echo ""

    if [ "$NEEDS_REBOOT" = true ]; then
        log_warn "IMPORTANT: System needs to reboot for cgroup changes to take effect."
        log_warn "The system will reboot automatically in 10 seconds..."
        sleep 10
        reboot
    else
        log_info "Setup completed successfully!"
    fi
}

main "$@"