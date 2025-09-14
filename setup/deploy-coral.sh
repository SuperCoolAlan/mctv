#!/bin/bash

# Deploy script to run Coral USB setup on Raspberry Pi
# This script copies and runs the setup script on the remote Raspberry Pi

set -e

echo "========================================="
echo "Deploy Coral USB Setup to Raspberry Pi"
echo "========================================="

# Load environment variables if .env exists
if [ -f "$(dirname "$0")/.env" ]; then
    source "$(dirname "$0")/.env"
fi

# Set default values if not in .env
RASPI_HOST=${RASPI_HOST:-"mctv3.local"}
RASPI_USER=${RASPI_USER:-"alan"}

echo "Target: $RASPI_USER@$RASPI_HOST"
echo ""

# Function to check SSH connectivity
check_ssh() {
    echo "Checking SSH connectivity to Raspberry Pi..."
    if ssh -o ConnectTimeout=5 "$RASPI_USER@$RASPI_HOST" "echo 'SSH connection successful'" 2>/dev/null; then
        echo "✓ SSH connection established"
        return 0
    else
        echo "✗ Cannot connect via SSH"
        echo "Please ensure:"
        echo "  1. Raspberry Pi is powered on"
        echo "  2. SSH key is configured"
        echo "  3. Network connectivity exists"
        return 1
    fi
}

# Function to check Coral USB on remote host
check_coral_remote() {
    echo "Checking for Coral USB device on Raspberry Pi..."
    
    CORAL_CHECK=$(ssh "$RASPI_USER@$RASPI_HOST" "lsusb | grep -E '(1a6e:089a|18d1:9302|Google.*Coral)' || echo 'not found'" 2>/dev/null)
    
    if [ "$CORAL_CHECK" != "not found" ]; then
        echo "✓ Found Coral device: $CORAL_CHECK"
        return 0
    else
        echo "⚠ Coral USB device not detected on Raspberry Pi"
        echo "  You can still set up the udev rules now and plug in the Coral later"
        return 1
    fi
}

# Function to check if Coral is already configured
check_coral_configured() {
    echo "Checking if Coral is already configured..."
    
    if ssh "$RASPI_USER@$RASPI_HOST" "[ -f /etc/coral-usb-configured ]" 2>/dev/null; then
        echo "✓ Coral USB already configured on Raspberry Pi"
        ssh "$RASPI_USER@$RASPI_HOST" "cat /etc/coral-usb-configured"
        return 0
    else
        echo "⚠ Coral USB not yet configured"
        return 1
    fi
}

# Function to deploy and run setup script
deploy_setup_script() {
    echo "Copying Coral setup script to Raspberry Pi..."
    
    SETUP_SCRIPT="$(dirname "$0")/setup-coral-usb.sh"
    
    if [ ! -f "$SETUP_SCRIPT" ]; then
        echo "Error: setup-coral-usb.sh not found at $SETUP_SCRIPT"
        exit 1
    fi
    
    # Copy the setup script
    scp "$SETUP_SCRIPT" "$RASPI_USER@$RASPI_HOST:/tmp/setup-coral-usb.sh"
    
    echo "Running Coral setup on Raspberry Pi..."
    ssh "$RASPI_USER@$RASPI_HOST" "sudo bash /tmp/setup-coral-usb.sh"
}

# Main execution
main() {
    echo "Starting Coral USB deployment..."
    echo ""
    
    # Check SSH connectivity
    if ! check_ssh; then
        exit 1
    fi
    
    echo ""
    
    # Check if already configured
    if check_coral_configured; then
        echo ""
        read -p "Coral is already configured. Reconfigure? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Skipping reconfiguration."
            echo ""
            echo "To deploy Frigate with Coral support:"
            echo "  1. Ensure the Coral manifests are in k0s/frigate/"
            echo "  2. Run: kubectl apply -k k0s/frigate/"
            exit 0
        fi
    fi
    
    echo ""
    
    # Check for Coral USB on remote
    check_coral_remote
    
    echo ""
    
    # Deploy and run setup script
    deploy_setup_script
    
    echo ""
    echo "========================================="
    echo "Coral USB deployment complete!"
    echo "========================================="
    echo ""
    echo "The Raspberry Pi is now configured for Coral USB support."
    echo ""
    echo "To deploy Frigate with Coral support:"
    echo "  1. Ensure k0s is installed and running"
    echo "  2. The manifests in k0s/frigate/ include:"
    echo "     - coral-usb-patch.yaml (deployment patch)"
    echo "     - frigate-coral-config.yaml (ConfigMap with Coral detector)"
    echo "     - kustomization.yaml (references both files)"
    echo "  3. Deploy with: kubectl apply -k k0s/frigate/"
    echo ""
    echo "To verify Coral is working after deployment:"
    echo "  - Visit https://momscloset.asandov.com"
    echo "  - Check System → System Info for 'coral' detector"
    echo "  - Monitor logs: kubectl logs -n frigate deployment/frigate"
}

# Run main function
main "$@"