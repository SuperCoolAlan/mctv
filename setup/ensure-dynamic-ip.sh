#!/bin/bash
# Script to ensure k0s uses dynamic IP addresses
# This prevents issues when moving between networks (ethernet/wifi)
# Fixes the common "etcd connection refused" error when switching networks

set -e

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Ensuring k0s uses dynamic IP configuration...${NC}"

# Function to check if k0s is running
check_k0s_status() {
    if systemctl is-active --quiet k0scontroller; then
        return 0
    else
        return 1
    fi
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run this script with sudo${NC}"
    exit 1
fi

# Check if k0s service exists
if [ -f /etc/systemd/system/k0scontroller.service ]; then
    echo "Checking k0s service configuration..."

    SERVICE_MODIFIED=false

    # Remove any hardcoded node-ip arguments
    if grep -q "node-ip=" /etc/systemd/system/k0scontroller.service; then
        echo -e "${YELLOW}Found hardcoded IP in k0s service, removing...${NC}"
        sed -i 's/--kubelet-extra-args=--node-ip=[0-9.]*//g' /etc/systemd/system/k0scontroller.service
        sed -i 's/--node-ip=[0-9.]*//g' /etc/systemd/system/k0scontroller.service
        SERVICE_MODIFIED=true
        echo -e "${GREEN}Hardcoded IP removed from service${NC}"
    else
        echo -e "${GREEN}No hardcoded IP found in service configuration${NC}"
    fi
fi

# Check k0s config file
if [ -f /etc/k0s/k0s.yaml ]; then
    echo "Checking k0s configuration file..."

    CONFIG_MODIFIED=false
    BACKUP_FILE="/etc/k0s/k0s.yaml.backup.$(date +%Y%m%d_%H%M%S)"

    # Backup the config
    cp /etc/k0s/k0s.yaml "$BACKUP_FILE"
    echo "Config backed up to: $BACKUP_FILE"

    # Remove hardcoded IPs from SANs list (except localhost)
    if grep -A5 'sans:' /etc/k0s/k0s.yaml | grep -E '^\s*- [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' | grep -v '127.0.0.1' > /dev/null; then
        echo -e "${YELLOW}Found hardcoded IPs in SANs list, removing...${NC}"
        # Remove any IP that's not 127.0.0.1 from the SANs list
        sed -i '/sans:/,/^[^ ]/{/- [0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}$/d; /- 127\.0\.0\.1$/!d}' /etc/k0s/k0s.yaml
        # Keep localhost and hostnames
        sed -i '/sans:/,/^[^ ]/{/- 127\.0\.0\.1$/p; /- localhost$/p; /- [a-zA-Z]/p}' /etc/k0s/k0s.yaml
        CONFIG_MODIFIED=true
        echo -e "${GREEN}Hardcoded IPs removed from SANs${NC}"
    fi

    # Update etcd peerAddress to use 0.0.0.0 (bind to all interfaces)
    if grep -q 'peerAddress:' /etc/k0s/k0s.yaml; then
        CURRENT_PEER=$(grep 'peerAddress:' /etc/k0s/k0s.yaml | awk '{print $2}')
        if [ "$CURRENT_PEER" != "0.0.0.0" ]; then
            echo -e "${YELLOW}Updating etcd peerAddress from '$CURRENT_PEER' to '0.0.0.0'...${NC}"
            sed -i 's/peerAddress:.*/peerAddress: 0.0.0.0/' /etc/k0s/k0s.yaml
            CONFIG_MODIFIED=true
            echo -e "${GREEN}etcd configured to bind to all interfaces${NC}"
        fi
    fi

    # Display what's in the config now
    echo "Current network configuration:"
    echo -n "  SANs: "
    grep -A10 'sans:' /etc/k0s/k0s.yaml | grep '^\s*-' | tr '\n' ' ' | sed 's/- //g' || echo "Not found"
    echo ""
    echo -n "  etcd peerAddress: "
    grep 'peerAddress:' /etc/k0s/k0s.yaml | awk '{print $2}' || echo "Not found"

    # Restart k0s if any changes were made
    if [ "$SERVICE_MODIFIED" = true ] || [ "$CONFIG_MODIFIED" = true ]; then
        echo -e "${YELLOW}Configuration changed, restarting k0s...${NC}"

        # Stop k0s
        systemctl stop k0scontroller || true

        # Reload systemd if service was modified
        if [ "$SERVICE_MODIFIED" = true ]; then
            systemctl daemon-reload
        fi

        # Start k0s
        systemctl start k0scontroller

        echo "Waiting for k0s to start..."
        sleep 10

        if check_k0s_status; then
            echo -e "${GREEN}k0s restarted successfully!${NC}"
        else
            echo -e "${RED}k0s failed to start. Check logs with: journalctl -u k0scontroller -n 50${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}No changes needed - configuration is already dynamic${NC}"
    fi
else
    echo -e "${RED}k0s config file not found at /etc/k0s/k0s.yaml${NC}"
    exit 1
fi

echo -e "${GREEN}Dynamic IP configuration complete!${NC}"
echo ""
echo "Your k0s cluster will now work across different networks without hardcoded IPs."
echo "The cluster will be accessible via:"
echo "  - Hostname: mctv4.local"
echo "  - Current IP: $(hostname -I | awk '{print $1}')"