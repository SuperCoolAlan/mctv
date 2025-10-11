#!/bin/bash
# Master installation script for MCTV k0s cluster
# This script automates the entire installation process

set -e

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."

    local missing=()
    command -v k0sctl &> /dev/null || missing+=("k0sctl")
    command -v kubectl &> /dev/null || missing+=("kubectl")
    command -v kustomize &> /dev/null || missing+=("kustomize")

    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing[*]}"
        log_info "Install with: brew install ${missing[*]}"
        exit 1
    fi

    if [ ! -f ~/.ssh/momscloset ]; then
        log_error "SSH key not found at ~/.ssh/momscloset"
        exit 1
    fi

    log_info "All prerequisites met"
}

# Wait for Pi to come back online
wait_for_pi() {
    log_info "Waiting for Pi to come back online..."
    for i in {1..60}; do
        if ping -c 1 -W 1 mctv3.local > /dev/null 2>&1; then
            log_info "Pi is responding to ping, waiting for SSH..."
            sleep 10
            for j in {1..30}; do
                if ssh -i ~/.ssh/momscloset -o ConnectTimeout=5 alan@mctv3.local "echo 'SSH is ready'" &>/dev/null; then
                    log_info "Pi is back online and SSH is ready!"
                    return 0
                fi
                sleep 2
            done
        fi
        echo -n "."
        sleep 2
    done
    log_error "Pi did not come back online after 2 minutes"
    return 1
}

# Phase 1: Initial Pi Setup
phase1_pi_setup() {
    log_step "Phase 1: Initial Raspberry Pi Setup"

    cd setup

    # Remove old SSH key if exists
    ssh-keygen -R mctv3.local 2>/dev/null || true
    ssh-keygen -R 10.0.1.16 2>/dev/null || true

    # Add new SSH key
    ssh -o StrictHostKeyChecking=accept-new -i ~/.ssh/momscloset alan@mctv3.local "echo 'SSH key accepted'" || true

    # Check if dpkg is locked (fresh boot updates)
    log_info "Checking if system updates are running..."
    local max_wait=60
    local waited=0
    while ssh -i ~/.ssh/momscloset alan@mctv3.local "sudo lsof /var/lib/dpkg/lock-frontend 2>/dev/null | grep -q dpkg" && [ $waited -lt $max_wait ]; do
        log_warn "System is running automatic updates, waiting... ($waited/$max_wait seconds)"
        sleep 10
        waited=$((waited + 10))
    done
    if [ $waited -ge $max_wait ]; then
        log_warn "System updates still running after $max_wait seconds, proceeding anyway"
    fi

    # Configure WiFi FIRST so it works after reboot
    log_info "Configuring WiFi for deployment..."
    if [ -f .env ]; then
        ./wifi-config.sh --remote
    else
        log_error "WiFi configuration file .env not found!"
        log_info "Please create setup/.env from setup/.env.template with WiFi credentials"
        exit 1
    fi

    # Run remote setup
    log_info "Running initial Pi setup (will configure cgroups, install dependencies)..."
    # Pass -y flag if we're in auto mode
    if [ "$AUTO_MODE" == "true" ]; then
        ./setup-remote.sh -y
    else
        ./setup-remote.sh
    fi

    cd ..

    # Check if Pi needs reboot after setup
    log_info "Checking if cgroups are active..."
    if ! ssh -i ~/.ssh/momscloset alan@mctv3.local "[ -d /sys/fs/cgroup/memory ] && [ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]" 2>/dev/null; then
        log_warn "Pi needs reboot for cgroups to be active. Rebooting now..."
        ssh -i ~/.ssh/momscloset alan@mctv3.local "sudo reboot" 2>/dev/null || true
        sleep 5
        wait_for_pi
    else
        log_info "Cgroups are already active, no reboot needed"
    fi

    log_info "Initial Pi setup completed successfully!"
}

# Phase 2: Deploy k0s with dynamic IP support
phase2_deploy_k0s() {
    log_step "Phase 2: Deploy k0s Cluster"

    cd setup

    # Use our dynamic deployment script
    log_info "Deploying k0s with dynamic IP support..."
    ./deploy-dynamic.sh

    cd ..

    # Wait for cluster to stabilize
    log_info "Waiting for cluster to stabilize..."
    sleep 30

    # Verify cluster
    export KUBECONFIG=~/.kube/clusters/mctv3.yaml
    local retries=5
    while [ $retries -gt 0 ]; do
        if kubectl get nodes 2>/dev/null | grep -q Ready; then
            break
        fi
        log_info "Waiting for cluster to be ready... ($retries attempts left)"
        sleep 10
        retries=$((retries - 1))
    done

    if ! kubectl get nodes | grep -q Ready; then
        log_error "Cluster not ready after waiting!"
        exit 1
    fi

    log_info "k0s cluster deployed successfully"

    # Ensure taint is removed for single-node cluster
    log_info "Ensuring control-plane taint is removed..."
    kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || log_info "Taint already removed"
}

# Phase 3: Deploy storage and services
phase3_deploy_services() {
    log_step "Phase 3: Deploy Services"

    export KUBECONFIG=~/.kube/clusters/mctv3.yaml

    # Deploy in order
    local services=(
        "k0s/local-path-provisioner"
        "k0s/cloudflare-tunnel"
        "k0s/frigate"
        "k0s/twingate"
    )

    for service in "${services[@]}"; do
        log_info "Deploying $service..."
        cd "$service"
        kustomize build --enable-exec --enable-alpha-plugins . | kubectl apply -f -
        cd - > /dev/null

        # Wait a bit between deployments
        sleep 10
    done

    # Wait for all pods to be ready
    log_info "Waiting for all services to start..."
    kubectl wait --for=condition=ready pod --all --all-namespaces --timeout=300s || true
}

# Phase 4: Post-deployment verification
phase4_verify() {
    log_step "Phase 4: Verification"

    export KUBECONFIG=~/.kube/clusters/mctv3.yaml

    # Check all pods
    log_info "Checking pod status..."
    kubectl get pods -A

    # Get Frigate password
    log_info "Getting Frigate admin password..."
    kubectl logs -n frigate deployment/frigate | grep -i "password:" || true

    # Check Coral detection
    log_info "Checking Coral TPU status..."
    kubectl logs -n frigate deployment/frigate | grep -i "tpu found" || true

    # Test Cloudflare tunnel
    log_info "Testing Cloudflare tunnel..."
    if curl -s -I https://momscloset.asandov.com | grep -q "401"; then
        log_info "✅ Cloudflare tunnel working (401 = auth required)"
    else
        log_warn "❌ Cloudflare tunnel may not be working"
    fi
}

# Main execution
main() {
    log_info "========================================="
    log_info "MCTV k0s Automated Installation"
    log_info "========================================="

    check_prerequisites

    # Check for auto mode
    AUTO_MODE=false
    if [ "$1" == "-y" ] || [ "$1" == "--yes" ]; then
        AUTO_MODE=true
        log_info "Running in auto-confirm mode"
    fi

    # Ask for confirmation
    echo ""
    log_warn "This will:"
    echo "  1. Configure WiFi for deployment (momscloset network)"
    echo "  2. Configure Raspberry Pi at mctv3.local"
    echo "  3. Deploy k0s cluster with dynamic IP support"
    echo "  4. Deploy all services (storage, Cloudflare, Frigate, Twingate)"
    echo "  5. Configure Frigate with Coral TPU support"
    echo ""

    if [ "$AUTO_MODE" != "true" ]; then
        read -p "Continue? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi

    # Run phases
    phase1_pi_setup
    phase2_deploy_k0s
    phase3_deploy_services
    phase4_verify

    log_info "========================================="
    log_info "Installation Complete!"
    log_info "========================================="
    log_info "Access Frigate at: https://momscloset.asandov.com"
    log_info "Don't forget to plug in the Coral USB device!"
}

main "$@"