#!/bin/bash

# Setup script for Coral USB TPU on Raspberry Pi
# This script configures the OS-level requirements for Coral USB
# Run this BEFORE installing k0s/Kubernetes

set -e

echo "========================================="
echo "Coral USB TPU Setup for Raspberry Pi"
echo "========================================="

# Function to detect Coral USB device
detect_coral() {
    echo "Checking for Coral USB device..."
    
    # Google Coral USB Accelerator vendor:product IDs
    # Standard: 1a6e:089a or 18d1:9302
    CORAL_DEVICE=$(lsusb | grep -E "(1a6e:089a|18d1:9302|Google.*Coral)" || true)
    
    if [ -z "$CORAL_DEVICE" ]; then
        echo "⚠ Warning: Coral USB device not detected!"
        echo "Please ensure the Coral USB is plugged in."
        echo "Expected device IDs: 1a6e:089a or 18d1:9302"
        echo ""
        echo "You can still set up the udev rules now and plug in the Coral later."
        echo "Continuing with setup anyway..."
        return 1
    else
        echo "✓ Found Coral device: $CORAL_DEVICE"
        
        # Extract bus and device numbers
        BUS=$(echo "$CORAL_DEVICE" | awk '{print $2}')
        DEVICE=$(echo "$CORAL_DEVICE" | awk '{print $4}' | tr -d ':')
        echo "  Bus: $BUS, Device: $DEVICE"
        
        # Get the device path
        DEVICE_PATH="/dev/bus/usb/$BUS/$DEVICE"
        if [ -e "$DEVICE_PATH" ]; then
            echo "  Device path: $DEVICE_PATH"
        fi
        
        return 0
    fi
}

# Function to install udev rules for Coral USB
setup_udev_rules() {
    echo ""
    echo "Setting up udev rules for Coral USB..."
    
    # Create udev rule for Coral USB
    cat <<EOF | sudo tee /etc/udev/rules.d/99-coral-usb.rules
# Google Coral USB Accelerator
SUBSYSTEMS=="usb", ATTRS{idVendor}=="1a6e", ATTRS{idProduct}=="089a", MODE="0666"
SUBSYSTEMS=="usb", ATTRS{idVendor}=="18d1", ATTRS{idProduct}=="9302", MODE="0666"
EOF
    
    # Reload udev rules
    sudo udevadm control --reload-rules
    sudo udevadm trigger
    
    echo "✓ udev rules configured"
}

# Function to install required packages
install_dependencies() {
    echo ""
    echo "Checking for required packages..."
    
    # Check if we're on Raspberry Pi OS / Debian
    if [ -f /etc/debian_version ]; then
        # Check if libusb is installed
        if ! dpkg -l | grep -q libusb-1.0-0; then
            echo "Installing libusb..."
            sudo apt-get update
            sudo apt-get install -y libusb-1.0-0
        else
            echo "✓ libusb already installed"
        fi
    else
        echo "⚠ Not running Debian/Raspberry Pi OS, skipping package installation"
    fi
}

# Function to install Edge TPU runtime at reduced frequency
install_edgetpu_runtime() {
    echo ""
    echo "Installing Edge TPU runtime (reduced frequency for safety)..."
    
    # Check if we're on Raspberry Pi OS / Debian
    if [ ! -f /etc/debian_version ]; then
        echo "⚠ Not running Debian/Raspberry Pi OS, skipping Edge TPU runtime installation"
        echo "  Please install the Edge TPU runtime manually for your OS"
        return
    fi
    
    # Check if runtime is already installed
    if dpkg -l | grep -q libedgetpu1-std; then
        echo "✓ Edge TPU runtime (standard/reduced frequency) already installed"
        return
    elif dpkg -l | grep -q libedgetpu1-max; then
        echo "⚠ Edge TPU runtime (maximum frequency) is installed"
        echo "  This runs at full power and can get very hot!"
        echo "  To switch to reduced frequency for safety:"
        echo "    sudo apt-get remove libedgetpu1-max"
        echo "    sudo apt-get install libedgetpu1-std"
        echo "Continuing with current runtime..."
        return
    fi
    
    # Add Coral repository if not already added
    if [ ! -f /etc/apt/sources.list.d/coral-edgetpu.list ]; then
        echo "Adding Coral repository..."
        echo "deb https://packages.cloud.google.com/apt coral-edgetpu-stable main" | sudo tee /etc/apt/sources.list.d/coral-edgetpu.list
        
        # Add repository key
        curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
        
        # Update package list
        sudo apt-get update
    fi
    
    # Install Edge TPU runtime (standard = reduced frequency)
    echo "Installing Edge TPU runtime at reduced frequency..."
    sudo apt-get install -y libedgetpu1-std
    
    echo "✓ Edge TPU runtime installed (reduced frequency mode)"
    echo ""
    echo "ℹ️  The runtime is configured for reduced frequency operation:"
    echo "   - Runs at half the maximum frequency"
    echo "   - Lower power consumption"
    echo "   - Safer temperature (won't get as hot)"
    echo "   - Still provides good performance for most use cases"
}

# Function to test Coral access
test_coral_access() {
    echo ""
    echo "Testing Coral USB access..."
    
    # Check if device exists and is accessible
    if lsusb | grep -E "(1a6e:089a|18d1:9302)" > /dev/null 2>&1; then
        echo "✓ Coral USB device is visible"
        
        # Check permissions
        BUS=$(lsusb | grep -E "(1a6e:089a|18d1:9302)" | awk '{print $2}')
        DEVICE=$(lsusb | grep -E "(1a6e:089a|18d1:9302)" | awk '{print $4}' | tr -d ':')
        DEVICE_PATH="/dev/bus/usb/$BUS/$DEVICE"
        
        if [ -r "$DEVICE_PATH" ] && [ -w "$DEVICE_PATH" ]; then
            echo "✓ Coral USB device is accessible (read/write permissions OK)"
        else
            echo "⚠ Coral USB device permissions may need adjustment"
            echo "  Device path: $DEVICE_PATH"
            ls -la "$DEVICE_PATH" 2>/dev/null || true
        fi
    else
        echo "⚠ Coral USB device not found - it can be connected later"
    fi
}

# Function to create a status file for later verification
create_status_file() {
    echo ""
    echo "Creating Coral setup status file..."
    
    STATUS_FILE="/etc/coral-usb-configured"
    echo "Coral USB setup completed on $(date)" | sudo tee "$STATUS_FILE" > /dev/null
    echo "✓ Status file created at $STATUS_FILE"
}

# Main execution
main() {
    echo "Starting Coral USB setup..."
    echo ""
    echo "This script will:"
    echo "  1. Detect Coral USB device (if connected)"
    echo "  2. Install udev rules for proper permissions"
    echo "  3. Install required dependencies"
    echo "  4. Install Edge TPU runtime (reduced frequency for safety)"
    echo "  5. Test device access"
    echo ""
    
    # Detect Coral USB device
    detect_coral
    CORAL_DETECTED=$?
    
    # Setup udev rules (always do this)
    setup_udev_rules
    
    # Install dependencies
    install_dependencies
    
    # Install Edge TPU runtime
    install_edgetpu_runtime
    
    # Test access if Coral was detected
    if [ $CORAL_DETECTED -eq 0 ]; then
        test_coral_access
    fi
    
    # Create status file
    create_status_file
    
    echo ""
    echo "========================================="
    echo "Coral USB setup complete!"
    echo "========================================="
    echo ""
    
    if [ $CORAL_DETECTED -eq 0 ]; then
        echo "✓ Coral USB device detected and configured"
    else
        echo "⚠ Coral USB device not detected, but rules are configured"
        echo "  You can plug in the Coral USB at any time"
    fi
    
    echo ""
    echo "The system is now ready for Coral USB support."
    echo "Edge TPU runtime is configured for reduced frequency (safer operation)."
    echo "When you deploy Frigate with Kubernetes, it will be able to access the Coral."
    echo ""
    echo "Next steps:"
    echo "  1. If Coral wasn't detected, plug it in and run: lsusb | grep -i coral"
    echo "  2. After plugging in Coral, it may need to be unplugged and replugged"
    echo "     to apply the new runtime settings"
    echo "  3. Continue with k0s installation if not already done"
    echo "  4. Deploy Frigate with Coral support using the manifests in k0s/frigate/"
    echo ""
    echo "Runtime Information:"
    echo "  - Installed: libedgetpu1-std (reduced frequency)"
    echo "  - Power: ~2W (vs ~4W at max frequency)"
    echo "  - Temperature: Runs cooler and safer"
    echo "  - Performance: Still excellent for object detection"
}

# Run main function
main "$@"