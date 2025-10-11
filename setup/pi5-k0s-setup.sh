#!/bin/bash
set -e

# Raspberry Pi 5 k0s Setup Script
# Based on: https://docs.k0sproject.io/stable/raspberry-pi5/

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Global auto-confirm flag
AUTO_CONFIRM=false

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running on Raspberry Pi
check_pi() {
    if [ -f /proc/cpuinfo ] && grep -q "Raspberry Pi 5" /proc/cpuinfo; then
        log_info "Detected Raspberry Pi 5"
    else
        if [ "$AUTO_CONFIRM" != "true" ]; then
            log_warn "This doesn't appear to be a Raspberry Pi 5. Continue anyway? (y/n)"
            read -r response
            if [ "$response" != "y" ]; then
                exit 1
            fi
        else
            log_warn "This doesn't appear to be a Raspberry Pi 5. Continuing anyway (auto-confirm)..."
        fi
    fi
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
        return 0
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
        if [ "$AUTO_CONFIRM" != "true" ]; then
            echo "Do you want to reinstall/update? (y/n)"
            read -r response
            if [ "$response" != "y" ]; then
                return 0
            fi
        else
            log_info "Auto-confirming k0s reinstall/update..."
        fi
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
    
    # Update system
    log_info "Updating system packages..."
    apt-get update
    apt-get upgrade -y
    
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
        ebtables
    
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

# Set up SSH key authentication
setup_ssh() {
    log_info "SSH Setup Instructions:"
    echo ""
    echo "From your workstation, run:"
    echo "  ssh-copy-id -i ~/.ssh/id_rsa.pub $(whoami)@$(hostname -I | awk '{print $1}')"
    echo ""
    echo "This will enable passwordless SSH access for k0sctl deployment."
    echo ""
    if [ "$AUTO_CONFIRM" != "true" ]; then
        echo "Press Enter to continue..."
        read -r
    fi
}

# Display next steps
show_next_steps() {
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    
    echo ""
    log_info "========================================="
    log_info "Raspberry Pi 5 k0s Setup Complete!"
    log_info "========================================="
    echo ""
    
    if [ "$NEEDS_REBOOT" = true ]; then
        log_warn "IMPORTANT: System needs to reboot for cgroup changes to take effect."
        echo ""
    fi
    
    echo "Next steps:"
    echo "1. Set up SSH key authentication (if not already done)"
    echo "2. From your workstation, install k0sctl:"
    echo "   - macOS/Linux: brew install k0sctl"
    echo "   - Or download from: https://github.com/k0sproject/k0sctl/releases"
    echo ""
    echo "3. Create a cluster.yaml file on your workstation with:"
    echo "   - Hostname: mctv3.local"
    echo "   - Username: $(whoami)"
    echo "   - SSH key path: ~/.ssh/id_rsa"
    echo ""
    echo "4. Deploy the cluster:"
    echo "   k0sctl apply --config cluster.yaml"
    echo ""
    echo "5. Get kubeconfig:"
    echo "   k0sctl kubeconfig --config cluster.yaml > kubeconfig"
    echo "   export KUBECONFIG=\$(pwd)/kubeconfig"
    echo ""
    echo "6. IMPORTANT: Run the dynamic IP script after deployment:"
    echo "   sudo ./ensure-dynamic-ip.sh"
    echo "   This prevents issues when switching between ethernet/wifi"
    echo ""
    
    if [ "$NEEDS_REBOOT" = true ]; then
        if [ "$AUTO_CONFIRM" != "true" ]; then
            echo "Reboot now? (y/n)"
            read -r response
            if [ "$response" = "y" ]; then
                reboot
            else
                log_warn "Please remember to reboot before deploying k0s!"
            fi
        else
            log_warn "System needs reboot. Auto-confirming NO to allow script to continue."
            log_warn "Please remember to reboot before deploying k0s!"
        fi
    fi
}

# Main execution
main() {
    echo "========================================="
    echo "Raspberry Pi 5 k0s Setup Script"
    echo "========================================="
    echo ""
    echo "This script will:"
    echo "1. Enable memory cgroups (required for k0s)"
    echo "2. Install k0s"
    echo "3. Configure system settings"
    echo "4. Prepare for k0sctl deployment"
    echo ""

    # Check for auto-confirm flag
    if [ "$1" == "-y" ] || [ "$1" == "--yes" ]; then
        AUTO_CONFIRM=true
        log_info "Auto-confirming setup..."
    else
        echo "Continue? (y/n)"
        read -r response
        if [ "$response" != "y" ]; then
            exit 0
        fi
    fi
    
    check_pi
    check_root
    enable_cgroups
    configure_system
    install_k0s
    setup_ssh
    show_next_steps
}

main "$@"