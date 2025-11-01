#!/bin/bash
set -e

# k0s Deployment Script with Dynamic IP Support
# This script ensures k0s is deployed without hardcoded IPs

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

# Prepare NVMe storage for k0s
prepare_nvme_storage() {
    log_info "Preparing NVMe storage on target host..."

    # Check if NVMe is already configured
    if ssh -i ~/.ssh/momscloset alan@mctv4.local "mount | grep -q '/mnt/nvme'" 2>/dev/null; then
        log_info "NVMe storage already mounted"
    else
        log_warn "NVMe storage not mounted, please ensure NVMe is properly configured"
        log_warn "Run the pi5-k0s-setup-auto.sh script on the Pi first to configure NVMe"
        return 1
    fi

    # Ensure k0s directory exists on NVMe
    ssh -i ~/.ssh/momscloset alan@mctv4.local "sudo mkdir -p /mnt/nvme/k0s && sudo chown root:root /mnt/nvme/k0s" || {
        log_error "Failed to create k0s directory on NVMe"
        return 1
    }

    return 0
}

# Deploy k0s with dynamic IP workaround
deploy_k0s_dynamic() {
    log_step "Deploying k0s with dynamic IP support..."

    # Ensure NVMe is ready
    if ! prepare_nvme_storage; then
        log_error "NVMe storage not ready, aborting deployment"
        exit 1
    fi

    # First, clean any existing installation
    log_info "Cleaning any existing k0s installation..."
    ssh -i ~/.ssh/momscloset alan@mctv4.local "sudo k0s reset --data-dir=/mnt/nvme/k0s 2>/dev/null || true; sudo systemctl stop k0scontroller 2>/dev/null || true; sudo systemctl disable k0scontroller 2>/dev/null || true; sudo rm -f /etc/systemd/system/k0scontroller.service; sudo systemctl daemon-reload; sudo rm -rf /mnt/nvme/k0s /etc/k0s" || true

    # Deploy with k0sctl
    log_info "Running k0sctl apply..."
    k0sctl apply --config cluster.yaml &
    APPLY_PID=$!

    # Wait a bit for the service to be created
    sleep 30

    # Monitor and fix the service if it gets created with hardcoded IP
    log_info "Monitoring for hardcoded IP issues..."
    for i in {1..20}; do
        if ssh -i ~/.ssh/momscloset alan@mctv4.local "test -f /etc/systemd/system/k0scontroller.service" 2>/dev/null; then
            log_info "Found k0s service, checking for hardcoded IP..."
            if ssh -i ~/.ssh/momscloset alan@mctv4.local "grep -q 'node-ip=' /etc/systemd/system/k0scontroller.service" 2>/dev/null; then
                log_warn "Found hardcoded IP, removing it..."
                ssh -i ~/.ssh/momscloset alan@mctv4.local "sudo sed -i 's/--kubelet-extra-args=--node-ip=[0-9.]*//g' /etc/systemd/system/k0scontroller.service && sudo systemctl daemon-reload && sudo systemctl restart k0scontroller"
                log_info "Hardcoded IP removed and service restarted"
            fi
            break
        fi
        sleep 5
    done

    # Wait for k0sctl to finish
    wait $APPLY_PID

    if [ $? -eq 0 ]; then
        log_info "k0s deployment completed!"

        # Final check and fix if needed
        if ssh -i ~/.ssh/momscloset alan@mctv4.local "grep -q 'node-ip=' /etc/systemd/system/k0scontroller.service" 2>/dev/null; then
            log_warn "Final cleanup of hardcoded IP..."
            ssh -i ~/.ssh/momscloset alan@mctv4.local "sudo sed -i 's/--kubelet-extra-args=--node-ip=[0-9.]*//g' /etc/systemd/system/k0scontroller.service && sudo systemctl daemon-reload && sudo systemctl restart k0scontroller"
        fi

        # Remove control-plane taint
        log_info "Removing control-plane taint for single-node cluster..."
        k0sctl kubeconfig --config cluster.yaml > /tmp/k0s-kubeconfig.yaml
        export KUBECONFIG=/tmp/k0s-kubeconfig.yaml
        kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true
        rm -f /tmp/k0s-kubeconfig.yaml
        unset KUBECONFIG

        return 0
    else
        log_error "k0s deployment failed"
        return 1
    fi
}

# Get kubeconfig
get_kubeconfig() {
    log_step "Retrieving kubeconfig..."

    KUBECONFIG_PATH="$HOME/.kube/clusters/mctv4.yaml"
    mkdir -p "$(dirname "$KUBECONFIG_PATH")"

    k0sctl kubeconfig --config cluster.yaml > "$KUBECONFIG_PATH"

    if [ $? -eq 0 ]; then
        log_info "Kubeconfig saved to $KUBECONFIG_PATH"
        echo ""
        echo "To use kubectl with this cluster:"
        echo "  export KUBECONFIG=$KUBECONFIG_PATH"
        echo "  kubectl get nodes"
    else
        log_error "Failed to retrieve kubeconfig"
        return 1
    fi
}

# Main execution
main() {
    log_info "Starting k0s deployment with dynamic IP support..."

    # Check prerequisites
    if ! command -v k0sctl &> /dev/null; then
        log_error "k0sctl is not installed"
        exit 1
    fi

    if [ ! -f cluster.yaml ]; then
        log_error "cluster.yaml not found"
        exit 1
    fi

    # Deploy k0s
    if deploy_k0s_dynamic; then
        # Get kubeconfig
        get_kubeconfig

        log_info "========================================="
        log_info "Deployment complete!"
        log_info "========================================="
    else
        log_error "Deployment failed"
        exit 1
    fi
}

main "$@"