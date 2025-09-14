#!/bin/bash
set -e

# Remote Setup Script for k0s on Raspberry Pi 5
# Copies and executes the setup script remotely

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

# Check prerequisites
check_prereq() {
    if [ ! -f pi5-k0s-setup.sh ]; then
        log_error "pi5-k0s-setup.sh not found in current directory"
        exit 1
    fi
    
    if [ ! -f ~/.ssh/momscloset ]; then
        log_error "SSH key not found at ~/.ssh/momscloset"
        exit 1
    fi
    
    # Test SSH connection
    if ! ssh -i ~/.ssh/momscloset -o ConnectTimeout=5 alan@mctv3.local "echo 'Connected'" &>/dev/null; then
        log_error "Cannot connect to alan@mctv3.local"
        echo "Please ensure:"
        echo "1. Raspberry Pi is powered on"
        echo "2. SSH is enabled"
        echo "3. SSH key is configured"
        exit 1
    fi
}

# Run setup remotely
run_setup() {
    log_info "Running k0s setup on Raspberry Pi 5..."
    log_info "Target: alan@mctv3.local"
    echo ""
    
    # Copy scripts to remote and execute setup (to handle interactive prompts)
    log_info "Copying setup scripts to remote host..."
    scp -i ~/.ssh/momscloset pi5-k0s-setup.sh alan@mctv3.local:/tmp/pi5-k0s-setup.sh
    
    # Also copy the Coral setup script for later use
    if [ -f setup-coral-usb.sh ]; then
        log_info "Copying Coral USB setup script..."
        scp -i ~/.ssh/momscloset setup-coral-usb.sh alan@mctv3.local:/home/alan/setup-coral-usb.sh
    fi
    
    # Execute the script remotely with TTY allocation for interactive prompts
    log_info "Executing setup script..."
    ssh -tt -i ~/.ssh/momscloset alan@mctv3.local "sudo bash /tmp/pi5-k0s-setup.sh"
    
    if [ $? -eq 0 ]; then
        log_info "Setup completed successfully!"
    else
        log_error "Setup failed"
        exit 1
    fi
}

# Main execution
main() {
    echo "========================================="
    echo "Remote k0s Setup for Raspberry Pi 5"
    echo "========================================="
    echo ""
    echo "This will copy and run the setup script on the Pi."
    echo "Target: alan@mctv3.local"
    echo ""
    echo "Continue? (y/n)"
    read -r response
    
    if [ "$response" != "y" ]; then
        exit 0
    fi
    
    check_prereq
    run_setup
    
    echo ""
    log_warn "If the Pi rebooted for cgroup changes, wait for it to come back online."
    log_info "Then run: ./deploy.sh to deploy the k0s cluster"
}

main "$@"