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

# Enable NVMe support for Raspberry Pi 5
enable_nvme() {
    log_info "Configuring NVMe support..."

    # Try both possible locations for config.txt
    CONFIG_FILE="/boot/firmware/config.txt"
    if [ ! -f "$CONFIG_FILE" ]; then
        CONFIG_FILE="/boot/config.txt"
    fi

    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Could not find config.txt in /boot/firmware/ or /boot/"
        exit 1
    fi

    # Backup original file
    cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

    # Check if PCIe is already enabled
    if grep -q "^dtparam=pciex1" "$CONFIG_FILE"; then
        log_info "PCIe for NVMe already enabled"
    else
        log_info "Adding PCIe configuration for NVMe to $CONFIG_FILE"
        # Add PCIe enable parameter
        echo "" >> "$CONFIG_FILE"
        echo "# Enable PCIe for NVMe" >> "$CONFIG_FILE"
        echo "dtparam=pciex1" >> "$CONFIG_FILE"

        log_warn "PCIe configuration added. System MUST be rebooted for changes to take effect."
        NEEDS_REBOOT=true
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
        ebtables \
        parted || {
        log_warn "Some tools failed to install, attempting to fix..."
        apt-get install -f -y
        dpkg --configure -a
        # Try again with individual packages to identify any problematic ones
        for pkg in curl wget vim htop net-tools iptables arptables ebtables parted; do
            apt-get install -y $pkg || log_warn "Failed to install $pkg"
        done
    }

    # Enable IP forwarding
    log_info "Enabling IP forwarding..."
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/99-k0s.conf
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.d/99-k0s.conf
    sysctl -p /etc/sysctl.d/99-k0s.conf

    # Configure WiFi to be ready for remote access
    log_info "Configuring WiFi..."
    # Unblock WiFi if blocked
    rfkill unblock wifi 2>/dev/null || true
    # Set WiFi country code
    raspi-config nonint do_wifi_country US 2>/dev/null || true
    # Bring up WiFi interface
    ip link set wlan0 up 2>/dev/null || true
    # Restart NetworkManager to ensure WiFi is available
    systemctl restart NetworkManager 2>/dev/null || true

    # Load required kernel modules
    log_info "Loading required kernel modules..."
    modprobe br_netfilter
    modprobe overlay

    # Make modules persistent
    echo "br_netfilter" >> /etc/modules-load.d/k0s.conf
    echo "overlay" >> /etc/modules-load.d/k0s.conf
}

# Configure NVMe storage if available
configure_nvme_storage() {
    log_info "Checking for NVMe storage..."

    # Check if NVMe device exists
    if [ -b /dev/nvme0n1 ]; then
        log_info "NVMe device detected at /dev/nvme0n1"

        # Check if already partitioned
        if ! lsblk /dev/nvme0n1 | grep -q nvme0n1p1; then
            log_info "Creating partition on NVMe drive..."
            # Create GPT partition table and single partition
            parted -s /dev/nvme0n1 mklabel gpt
            parted -s /dev/nvme0n1 mkpart primary ext4 0% 100%

            # Wait for partition to appear
            sleep 2

            # Format the partition
            log_info "Formatting NVMe partition..."
            mkfs.ext4 -F /dev/nvme0n1p1
        else
            log_info "NVMe already partitioned"

            # Check if partition has a filesystem
            if ! blkid /dev/nvme0n1p1 | grep -q "TYPE="; then
                log_info "Partition exists but no filesystem detected, formatting..."
                mkfs.ext4 -F /dev/nvme0n1p1
            else
                # Get filesystem type
                FS_TYPE=$(blkid -o value -s TYPE /dev/nvme0n1p1)
                log_info "NVMe partition already formatted with $FS_TYPE filesystem"

                # Warn if not ext4
                if [ "$FS_TYPE" != "ext4" ]; then
                    log_warn "NVMe is formatted as $FS_TYPE, not ext4. This may work but ext4 is recommended."
                fi
            fi
        fi

        # Create mount point
        mkdir -p /mnt/nvme

        # Check if already in fstab
        if ! grep -q "/dev/nvme0n1p1" /etc/fstab; then
            log_info "Adding NVMe to /etc/fstab..."
            echo "/dev/nvme0n1p1 /mnt/nvme ext4 defaults,noatime 0 2" >> /etc/fstab
        else
            log_info "NVMe already in /etc/fstab"
        fi

        # Mount if not already mounted
        if ! mount | grep -q "/mnt/nvme"; then
            log_info "Mounting NVMe drive..."
            mount /mnt/nvme
        fi

        # Create data directories for k0s
        log_info "Creating k0s data directories on NVMe..."
        mkdir -p /mnt/nvme/k0s
        mkdir -p /mnt/nvme/containerd

        # Create symlinks for k0s to use NVMe storage
        if [ ! -L /var/lib/k0s ]; then
            if [ -d /var/lib/k0s ]; then
                log_warn "/var/lib/k0s exists as a directory, k0s may already be installed"
                log_warn "To use NVMe storage, k0s should be installed fresh or migrated manually"
            else
                mkdir -p /mnt/nvme/k0s
                ln -s /mnt/nvme/k0s /var/lib/k0s
                log_info "Created symlink for k0s to use NVMe storage"
            fi
        else
            log_info "k0s already configured to use symlinked storage"
        fi

        if [ ! -L /var/lib/containerd ]; then
            if [ -d /var/lib/containerd ]; then
                log_warn "/var/lib/containerd exists as a directory"
                log_warn "To use NVMe storage for containerd, it should be migrated manually"
            else
                mkdir -p /mnt/nvme/containerd
                ln -s /mnt/nvme/containerd /var/lib/containerd
                log_info "Created symlink for containerd to use NVMe storage"
            fi
        else
            log_info "containerd already configured to use symlinked storage"
        fi

        log_info "NVMe storage configured successfully"
    else
        log_info "No NVMe device detected, continuing with SD card storage"
    fi
}

# Main execution
main() {
    echo "========================================="
    echo "Raspberry Pi 5 k0s Setup Script (Auto)"
    echo "========================================="
    echo ""
    log_info "Running in non-interactive mode"

    check_root
    enable_nvme
    enable_cgroups
    configure_system
    configure_nvme_storage
    install_k0s

    echo ""
    log_info "========================================="
    log_info "Raspberry Pi 5 k0s Setup Complete!"
    log_info "========================================="
    echo ""

    if [ "$NEEDS_REBOOT" = true ]; then
        log_warn "IMPORTANT: System needs to reboot for configuration changes to take effect."
        log_warn "The system will reboot automatically in 10 seconds..."
        sleep 10
        reboot
    else
        log_info "Setup completed successfully!"
    fi
}

main "$@"