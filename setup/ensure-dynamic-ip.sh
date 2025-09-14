#!/bin/bash
# Script to ensure k0s uses dynamic IP addresses
# This prevents issues when moving between networks

set -e

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}Ensuring k0s uses dynamic IP configuration...${NC}"

# Check if k0s service exists
if [ -f /etc/systemd/system/k0scontroller.service ]; then
    echo "Checking k0s service configuration..."

    # Remove any hardcoded node-ip arguments
    if grep -q "node-ip=" /etc/systemd/system/k0scontroller.service; then
        echo -e "${YELLOW}Found hardcoded IP in k0s service, removing...${NC}"
        sudo sed -i 's/--kubelet-extra-args=--node-ip=[0-9.]*//g' /etc/systemd/system/k0scontroller.service
        sudo sed -i 's/--node-ip=[0-9.]*//g' /etc/systemd/system/k0scontroller.service

        # Reload and restart service
        sudo systemctl daemon-reload
        sudo systemctl restart k0scontroller

        echo -e "${GREEN}Hardcoded IP removed and service restarted${NC}"
    else
        echo -e "${GREEN}No hardcoded IP found in service configuration${NC}"
    fi
fi

# Check k0s config file
if [ -f /etc/k0s/k0s.yaml ]; then
    echo "Checking k0s configuration file..."

    # Ensure no hardcoded IPs in config
    if grep -q "address: 10\." /etc/k0s/k0s.yaml; then
        echo -e "${YELLOW}Warning: Found potential hardcoded IP in k0s.yaml${NC}"
        echo "Please review /etc/k0s/k0s.yaml and remove any hardcoded IPs"
    fi
fi

echo -e "${GREEN}Dynamic IP check complete!${NC}"