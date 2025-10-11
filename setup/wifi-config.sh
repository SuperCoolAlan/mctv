#!/bin/bash
set -e

# WiFi Configuration Script for Raspberry Pi 5
# This configures the WiFi network connection for deployment

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
else
    echo "Error: .env file not found at $SCRIPT_DIR/.env"
    echo "Please copy .env.template to .env and fill in your credentials"
    exit 1
fi

# Validate required environment variables
required_vars=("WIFI_SSID" "WIFI_PASSWORD" "WIFI_COUNTRY" "SSH_KEY_PATH" "SSH_USER" "SSH_HOST")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Error: $var is not set in .env file"
        exit 1
    fi
done

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

# WiFi credentials loaded from .env file
# WIFI_SSID, WIFI_PASSWORD, and WIFI_COUNTRY are set from environment

# Configure WiFi using NetworkManager (default on Raspberry Pi OS)
configure_networkmanager() {
    log_info "Configuring WiFi using NetworkManager..."
    
    # Create connection
    nmcli dev wifi connect "$WIFI_SSID" password "$WIFI_PASSWORD" 2>/dev/null || {
        log_warn "Connection might already exist, updating..."
        nmcli connection modify "$WIFI_SSID" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$WIFI_PASSWORD"
    }
    
    # Set connection to auto-connect
    nmcli connection modify "$WIFI_SSID" connection.autoconnect yes
    nmcli connection modify "$WIFI_SSID" connection.autoconnect-priority 100
    
    log_info "WiFi configured with NetworkManager"
}

# Configure WiFi using wpa_supplicant (fallback method)
configure_wpa_supplicant() {
    log_info "Configuring WiFi using wpa_supplicant..."
    
    WPA_CONF="/etc/wpa_supplicant/wpa_supplicant.conf"
    
    # Backup existing configuration
    if [ -f "$WPA_CONF" ]; then
        cp "$WPA_CONF" "${WPA_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Generate encrypted password
    WPA_PSK=$(wpa_passphrase "$WIFI_SSID" "$WIFI_PASSWORD" | grep -E '^\s*psk=' | cut -d= -f2)
    
    # Create or update wpa_supplicant configuration
    cat > "$WPA_CONF" << EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=$WIFI_COUNTRY

network={
    ssid="$WIFI_SSID"
    psk=$WPA_PSK
    key_mgmt=WPA-PSK
    proto=RSN
    pairwise=CCMP
    auth_alg=OPEN
    priority=100
}
EOF
    
    # Enable wpa_supplicant service
    systemctl enable wpa_supplicant
    systemctl restart wpa_supplicant
    
    log_info "WiFi configured with wpa_supplicant"
}

# Configure WiFi in boot partition (for headless setup)
configure_boot_wifi() {
    log_info "Creating WiFi configuration for boot partition..."
    
    # This is useful for initial headless setup
    cat > wpa_supplicant.conf << EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=$WIFI_COUNTRY

network={
    ssid="$WIFI_SSID"
    psk="$WIFI_PASSWORD"
    key_mgmt=WPA-PSK
    priority=100
}
EOF
    
    log_info "Created wpa_supplicant.conf"
    echo "Copy this file to the boot partition of the SD card for headless WiFi setup"
}


# Test connectivity
test_connection() {
    log_info "Testing network connectivity..."
    
    # Wait for connection
    sleep 5
    
    # Check if interface is up
    if ip link show wlan0 | grep -q "state UP"; then
        log_info "WiFi interface is up"
    else
        log_warn "WiFi interface might not be up yet"
    fi
    
    # Get IP address
    IP_ADDR=$(ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    if [ -n "$IP_ADDR" ]; then
        log_info "IP address: $IP_ADDR"
    else
        log_warn "No IP address assigned yet"
    fi
    
    # Test internet connectivity
    if ping -c 1 8.8.8.8 &>/dev/null; then
        log_info "Internet connectivity: OK"
    else
        log_warn "Cannot reach internet"
    fi
    
    # Test DNS
    if ping -c 1 google.com &>/dev/null; then
        log_info "DNS resolution: OK"
    else
        log_warn "DNS resolution failed"
    fi
}

# Remote execution function
run_remote() {
    log_info "Configuring WiFi on remote Raspberry Pi..."
    
    ssh -T -i "$SSH_KEY_PATH" "$SSH_USER@$SSH_HOST" << REMOTE_SCRIPT
#!/bin/bash
set -e

WIFI_SSID="$WIFI_SSID"
WIFI_PASSWORD="$WIFI_PASSWORD"
WIFI_COUNTRY="$WIFI_COUNTRY"

echo "Configuring WiFi on $(hostname)..."

# Use NetworkManager if available
if command -v nmcli &> /dev/null; then
    echo "Using NetworkManager to create WiFi profile..."
    
    # Check if connection already exists
    if nmcli connection show "$WIFI_SSID" &>/dev/null; then
        echo "Updating existing connection profile..."
        sudo nmcli connection delete "$WIFI_SSID"
    fi
    
    # Create a new connection profile (works even if network is not available)
    echo "Creating WiFi connection profile for future use..."
    sudo nmcli connection add type wifi con-name "$WIFI_SSID" \
        ifname wlan0 ssid "$WIFI_SSID" \
        wifi-sec.key-mgmt wpa-psk \
        wifi-sec.psk "$WIFI_PASSWORD" \
        connection.autoconnect yes \
        connection.autoconnect-priority 100
    
    echo "WiFi profile created. Will auto-connect when network is available."
else
    echo "Using wpa_supplicant..."
    WPA_CONF="/etc/wpa_supplicant/wpa_supplicant.conf"
    
    # Backup existing
    [ -f "$WPA_CONF" ] && sudo cp "$WPA_CONF" "${WPA_CONF}.backup"
    
    # Generate config
    # Check if wpa_passphrase is available, if not, use plain password
    if command -v wpa_passphrase &> /dev/null; then
        WPA_PSK=$(wpa_passphrase "$WIFI_SSID" "$WIFI_PASSWORD" | grep -E '^\s*psk=' | cut -d= -f2)
    else
        echo "wpa_passphrase not found, using plain password (less secure)"
        WPA_PSK="\"$WIFI_PASSWORD\""
    fi
    
    sudo tee "$WPA_CONF" > /dev/null << EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=$WIFI_COUNTRY

network={
    ssid="$WIFI_SSID"
    psk=$WPA_PSK
    key_mgmt=WPA-PSK
    proto=RSN
    pairwise=CCMP
    auth_alg=OPEN
    priority=100
}
EOF
    
    sudo systemctl enable wpa_supplicant
    sudo systemctl restart wpa_supplicant
fi

# Verify configuration
echo ""
echo "Verifying WiFi configuration..."
if command -v nmcli &> /dev/null; then
    # Show the created connection profile
    nmcli connection show "$WIFI_SSID" | grep -E "(ssid|autoconnect|priority)" || true
    echo ""
    echo "WiFi profile status:"
    if nmcli connection show | grep -q "$WIFI_SSID"; then
        echo "✓ WiFi profile '$WIFI_SSID' created successfully"
        echo "✓ Will auto-connect when network is available at deployment site"
    else
        echo "✗ Failed to create WiFi profile"
    fi
else
    # Check wpa_supplicant config
    if [ -f "/etc/wpa_supplicant/wpa_supplicant.conf" ] && grep -q "$WIFI_SSID" /etc/wpa_supplicant/wpa_supplicant.conf; then
        echo "✓ WiFi configuration added to wpa_supplicant"
        echo "✓ Will auto-connect when network is available at deployment site"
    else
        echo "✗ Failed to configure wpa_supplicant"
    fi
fi

echo ""
echo "Current network status:"
ip addr show wlan0 2>/dev/null | grep -E "(state|inet)" || echo "WiFi interface: ready for deployment"

REMOTE_SCRIPT
    
    log_info "WiFi configuration completed on remote device"
}

# Main menu
show_menu() {
    echo ""
    echo "========================================="
    echo "WiFi Configuration for Raspberry Pi"
    echo "========================================="
    echo "Network: $WIFI_SSID"
    echo ""
    echo "1. Configure WiFi on remote Pi (via SSH)"
    echo "2. Generate wpa_supplicant.conf for SD card"
    echo "3. Show current configuration"
    echo "4. Test connection (remote)"
    echo "5. Exit"
    echo ""
    echo -n "Select an option: "
}

# Show current configuration
show_config() {
    echo ""
    echo "Current WiFi Configuration:"
    echo "=========================="
    echo "SSID: $WIFI_SSID"
    echo "Password: [hidden]"
    echo "Country: $WIFI_COUNTRY"
    echo ""
    echo "To deploy this configuration:"
    echo "1. Run option 1 to configure remotely via SSH"
    echo "2. Or use option 2 to generate config for SD card"
}

# Main execution
main() {
    # Check if running locally or should execute remotely
    if [ "$1" = "--remote" ]; then
        run_remote
        exit 0
    fi
    
    while true; do
        show_menu
        read -r option
        
        case $option in
            1)
                run_remote
                ;;
            2)
                configure_boot_wifi
                ;;
            3)
                show_config
                ;;
            4)
                ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SSH_HOST" "$(declare -f test_connection); $(declare -f log_info); $(declare -f log_warn); test_connection"
                ;;
            5)
                exit 0
                ;;
            *)
                log_error "Invalid option"
                ;;
        esac
    done
}

# Check if running as root (for local execution)
if [ "$EUID" -eq 0 ] && [ "$1" != "--remote" ]; then
    # Running as root locally
    configure_networkmanager || configure_wpa_supplicant
    test_connection
else
    # Running as regular user or remote execution
    main "$@"
fi