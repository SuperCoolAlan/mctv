#!/bin/bash
set -e

# k0s Deployment Script for Raspberry Pi 5
# This script automates the deployment process

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."
    
    # Check if k0sctl is installed
    if ! command -v k0sctl &> /dev/null; then
        log_error "k0sctl is not installed"
        echo "Install k0sctl using one of the following methods:"
        echo "  brew install k0sctl"
        echo "  Or download from: https://github.com/k0sproject/k0sctl/releases"
        exit 1
    fi
    
    log_info "k0sctl version: $(k0sctl version)"
    
    # Check SSH key
    if [ ! -f ~/.ssh/momscloset ]; then
        log_error "SSH private key not found at ~/.ssh/momscloset"
        exit 1
    fi
    
    # Check cluster config
    if [ ! -f cluster.yaml ]; then
        log_error "cluster.yaml not found in current directory"
        exit 1
    fi
    
    log_info "All prerequisites met"
}

# Upload SSH key to Raspberry Pi
setup_ssh() {
    log_step "Setting up SSH authentication..."
    
    echo "Uploading SSH public key to Raspberry Pi..."
    echo "You may be prompted for the password for alan@mctv3.local"
    
    if ssh-copy-id -i ~/.ssh/momscloset.pub alan@mctv3.local 2>/dev/null; then
        log_info "SSH key uploaded successfully"
    else
        log_warn "SSH key may already be configured or upload failed"
    fi
    
    # Test SSH connection
    log_info "Testing SSH connection..."
    if ssh -i ~/.ssh/momscloset -o ConnectTimeout=5 alan@mctv3.local "echo 'SSH connection successful'" &>/dev/null; then
        log_info "SSH connection test passed"
    else
        log_error "Cannot connect to mctv3.local via SSH"
        echo "Please ensure:"
        echo "1. The Raspberry Pi is powered on and connected to the network"
        echo "2. SSH is enabled on the Raspberry Pi"
        echo "3. The hostname 'mctv3.local' is resolvable"
        exit 1
    fi
}

# Run the setup script on Raspberry Pi
prepare_pi() {
    log_step "Preparing Raspberry Pi for k0s..."
    
    echo "Do you want to run the setup script on the Raspberry Pi? (y/n)"
    echo "This will configure cgroups, install k0s, and prepare the system."
    read -r response
    
    if [ "$response" = "y" ]; then
        log_info "Copying setup script to Raspberry Pi..."
        scp -i ~/.ssh/momscloset pi5-k0s-setup.sh alan@mctv3.local:/tmp/
        
        log_info "Running setup script on Raspberry Pi..."
        ssh -i ~/.ssh/momscloset alan@mctv3.local "sudo bash /tmp/pi5-k0s-setup.sh"
        
        log_warn "If the Pi rebooted for cgroup changes, wait for it to come back online and run this script again."
    fi
}

# Deploy k0s cluster
deploy_cluster() {
    log_step "Deploying k0s cluster..."
    
    log_info "Running k0sctl apply..."
    k0sctl apply --config cluster.yaml
    
    if [ $? -eq 0 ]; then
        log_info "Cluster deployed successfully!"
    else
        log_error "Cluster deployment failed"
        exit 1
    fi
}

# Get and save kubeconfig
get_kubeconfig() {
    log_step "Retrieving kubeconfig..."
    
    # Ask user where to save the kubeconfig
    echo ""
    echo "Where would you like to save the kubeconfig file?"
    echo "1. Current directory (./kubeconfig.yaml)"
    echo "2. ~/.kube/config (default kubectl location)"
    echo "3. Custom path"
    echo -n "Select an option (1-3): "
    read -r save_option
    
    case $save_option in
        1)
            KUBECONFIG_PATH="./kubeconfig.yaml"
            ;;
        2)
            KUBECONFIG_PATH="$HOME/.kube/config"
            mkdir -p "$HOME/.kube"
            # Backup existing config if it exists
            if [ -f "$HOME/.kube/config" ]; then
                cp "$HOME/.kube/config" "$HOME/.kube/config.backup.$(date +%Y%m%d_%H%M%S)"
                log_info "Existing kubeconfig backed up"
            fi
            ;;
        3)
            echo -n "Enter custom path: "
            read -r KUBECONFIG_PATH
            # Expand tilde if present
            KUBECONFIG_PATH="${KUBECONFIG_PATH/#\~/$HOME}"
            # Create directory if it doesn't exist
            mkdir -p "$(dirname "$KUBECONFIG_PATH")"
            ;;
        *)
            log_error "Invalid option"
            return 1
            ;;
    esac
    
    # Retrieve and save kubeconfig
    k0sctl kubeconfig --config cluster.yaml > "$KUBECONFIG_PATH"
    
    if [ $? -eq 0 ]; then
        log_info "Kubeconfig saved to $KUBECONFIG_PATH"
        echo ""
        
        if [ "$save_option" = "2" ]; then
            echo "kubectl is now configured to use this cluster by default"
            echo "Test with: kubectl get nodes"
        else
            echo "To use kubectl with this cluster:"
            echo "  export KUBECONFIG=$KUBECONFIG_PATH"
            echo "  kubectl get nodes"
        fi
    else
        log_error "Failed to retrieve kubeconfig"
        exit 1
    fi
}

# Verify cluster health
verify_cluster() {
    log_step "Verifying cluster health..."
    
    export KUBECONFIG=$(pwd)/kubeconfig.yaml
    
    if command -v kubectl &> /dev/null; then
        log_info "Checking node status..."
        kubectl get nodes
        
        echo ""
        log_info "Checking system pods..."
        kubectl get pods -A
    else
        log_warn "kubectl not installed, skipping verification"
        echo "Install kubectl to verify cluster status"
    fi
}

# Create backup of configuration
backup_config() {
    log_step "Creating configuration backup..."
    
    BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    cp cluster.yaml "$BACKUP_DIR/"
    cp kubeconfig.yaml "$BACKUP_DIR/" 2>/dev/null || true
    
    log_info "Configuration backed up to $BACKUP_DIR"
}

# Main menu
show_menu() {
    echo ""
    echo "========================================="
    echo "k0s Raspberry Pi Deployment Tool"
    echo "========================================="
    echo "1. Full deployment (all steps)"
    echo "2. Setup SSH authentication only"
    echo "3. Prepare Raspberry Pi only"
    echo "4. Deploy cluster only"
    echo "5. Get kubeconfig only"
    echo "6. Verify cluster health"
    echo "7. Backup configuration"
    echo "8. Exit"
    echo ""
    echo -n "Select an option: "
}

# Main execution
main() {
    while true; do
        show_menu
        read -r option
        
        case $option in
            1)
                check_prerequisites
                setup_ssh
                prepare_pi
                deploy_cluster
                get_kubeconfig
                verify_cluster
                backup_config
                break
                ;;
            2)
                setup_ssh
                ;;
            3)
                prepare_pi
                ;;
            4)
                check_prerequisites
                deploy_cluster
                ;;
            5)
                get_kubeconfig
                ;;
            6)
                verify_cluster
                ;;
            7)
                backup_config
                ;;
            8)
                exit 0
                ;;
            *)
                log_error "Invalid option"
                ;;
        esac
    done
    
    echo ""
    log_info "========================================="
    log_info "Deployment complete!"
    log_info "========================================="
}

main "$@"