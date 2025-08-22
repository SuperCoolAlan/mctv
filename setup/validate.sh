#!/bin/bash
set -e

# k0s Cluster Validation Script
# Comprehensive health checks for k0s on Raspberry Pi 5

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASS_COUNT++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAIL_COUNT++))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARN_COUNT++))
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check SSH connectivity
check_ssh() {
    log_info "Checking SSH connectivity..."
    
    if ssh -i ~/.ssh/momscloset -o ConnectTimeout=5 alan@mctv3.local "echo 'connected'" &>/dev/null; then
        log_pass "SSH connection to mctv3.local"
    else
        log_fail "Cannot connect to mctv3.local via SSH"
        return 1
    fi
}

# Check Raspberry Pi system
check_pi_system() {
    log_info "Checking Raspberry Pi system..."
    
    # Check OS version
    OS_INFO=$(ssh -i ~/.ssh/momscloset alan@mctv3.local "cat /etc/os-release | grep PRETTY_NAME" 2>/dev/null || echo "Unknown")
    log_info "OS: $OS_INFO"
    
    # Check cgroups
    if ssh -i ~/.ssh/momscloset alan@mctv3.local "grep -q 'cgroup_enable=memory' /boot/cmdline.txt" 2>/dev/null; then
        log_pass "Memory cgroups enabled"
    else
        log_fail "Memory cgroups not enabled in /boot/cmdline.txt"
    fi
    
    # Check memory
    MEM_INFO=$(ssh -i ~/.ssh/momscloset alan@mctv3.local "free -h | grep Mem" 2>/dev/null)
    log_info "Memory: $MEM_INFO"
    
    # Check disk space
    DISK_INFO=$(ssh -i ~/.ssh/momscloset alan@mctv3.local "df -h / | tail -1" 2>/dev/null)
    DISK_USAGE=$(echo "$DISK_INFO" | awk '{print $5}' | sed 's/%//')
    
    if [ "$DISK_USAGE" -lt 80 ]; then
        log_pass "Disk usage acceptable ($DISK_USAGE%)"
    elif [ "$DISK_USAGE" -lt 90 ]; then
        log_warn "Disk usage high ($DISK_USAGE%)"
    else
        log_fail "Disk usage critical ($DISK_USAGE%)"
    fi
    
    # Check system load
    LOAD=$(ssh -i ~/.ssh/momscloset alan@mctv3.local "uptime" 2>/dev/null)
    log_info "Load: $LOAD"
}

# Check k0s installation
check_k0s_install() {
    log_info "Checking k0s installation..."
    
    if ssh -i ~/.ssh/momscloset alan@mctv3.local "command -v k0s" &>/dev/null; then
        K0S_VERSION=$(ssh -i ~/.ssh/momscloset alan@mctv3.local "k0s version" 2>/dev/null)
        log_pass "k0s installed: $K0S_VERSION"
    else
        log_fail "k0s not installed"
        return 1
    fi
    
    # Check k0s service
    if ssh -i ~/.ssh/momscloset alan@mctv3.local "sudo systemctl is-active k0scontroller" &>/dev/null; then
        log_pass "k0s controller service running"
    else
        log_warn "k0s controller service not running"
    fi
    
    if ssh -i ~/.ssh/momscloset alan@mctv3.local "sudo systemctl is-active k0sworker" &>/dev/null; then
        log_pass "k0s worker service running"
    else
        # This might be expected if using controller+worker mode
        log_info "k0s worker service not running (may be in controller+worker mode)"
    fi
}

# Check Kubernetes cluster
check_cluster() {
    log_info "Checking Kubernetes cluster..."
    
    # Check for kubeconfig
    if [ ! -f kubeconfig.yaml ]; then
        log_warn "kubeconfig.yaml not found, trying to retrieve..."
        k0sctl kubeconfig --config cluster.yaml > kubeconfig.yaml 2>/dev/null || {
            log_fail "Cannot retrieve kubeconfig"
            return 1
        }
    fi
    
    export KUBECONFIG=$(pwd)/kubeconfig.yaml
    
    # Check kubectl availability
    if ! command -v kubectl &> /dev/null; then
        log_warn "kubectl not installed locally, skipping cluster checks"
        return 0
    fi
    
    # Check API server
    if kubectl version --short &>/dev/null; then
        log_pass "API server reachable"
    else
        log_fail "Cannot reach API server"
        return 1
    fi
    
    # Check nodes
    NODE_STATUS=$(kubectl get nodes --no-headers 2>/dev/null)
    if [ -n "$NODE_STATUS" ]; then
        if echo "$NODE_STATUS" | grep -q "Ready"; then
            log_pass "Node is Ready"
            echo "  $NODE_STATUS"
        else
            log_fail "Node not Ready"
            echo "  $NODE_STATUS"
        fi
    else
        log_fail "No nodes found"
    fi
    
    # Check system pods
    log_info "Checking system pods..."
    FAILED_PODS=$(kubectl get pods -A --no-headers 2>/dev/null | grep -v "Running\|Completed" || true)
    
    if [ -z "$FAILED_PODS" ]; then
        log_pass "All system pods healthy"
    else
        log_warn "Some pods not healthy:"
        echo "$FAILED_PODS" | while read line; do
            echo "  $line"
        done
    fi
    
    # Check core components
    for ns in kube-system; do
        POD_COUNT=$(kubectl get pods -n $ns --no-headers 2>/dev/null | wc -l)
        if [ "$POD_COUNT" -gt 0 ]; then
            log_pass "$ns namespace has $POD_COUNT pods"
        else
            log_warn "$ns namespace is empty"
        fi
    done
}

# Check network connectivity
check_network() {
    log_info "Checking network configuration..."
    
    # Check if required ports are open
    PORTS=(6443 10250 2380 9443)
    for port in "${PORTS[@]}"; do
        if nc -zv mctv3.local $port &>/dev/null; then
            log_pass "Port $port is accessible"
        else
            log_warn "Port $port is not accessible"
        fi
    done
    
    # Check DNS resolution from cluster
    if [ -f kubeconfig.yaml ]; then
        export KUBECONFIG=$(pwd)/kubeconfig.yaml
        if command -v kubectl &> /dev/null; then
            if kubectl run dns-test --image=busybox:latest --rm -it --restart=Never -- nslookup kubernetes.default &>/dev/null; then
                log_pass "Cluster DNS working"
            else
                log_warn "Cluster DNS test failed"
            fi
        fi
    fi
}

# Performance check
check_performance() {
    log_info "Checking performance metrics..."
    
    # Check CPU temperature (Raspberry Pi specific)
    TEMP=$(ssh -i ~/.ssh/momscloset alan@mctv3.local "vcgencmd measure_temp 2>/dev/null" || echo "temp=unknown")
    TEMP_VALUE=$(echo "$TEMP" | sed 's/temp=//' | sed "s/'C//")
    
    if [ "$TEMP_VALUE" != "unknown" ]; then
        TEMP_NUM=$(echo "$TEMP_VALUE" | cut -d. -f1)
        if [ "$TEMP_NUM" -lt 70 ]; then
            log_pass "CPU temperature normal ($TEMP_VALUE°C)"
        elif [ "$TEMP_NUM" -lt 80 ]; then
            log_warn "CPU temperature elevated ($TEMP_VALUE°C)"
        else
            log_fail "CPU temperature high ($TEMP_VALUE°C)"
        fi
    fi
    
    # Check throttling
    THROTTLE=$(ssh -i ~/.ssh/momscloset alan@mctv3.local "vcgencmd get_throttled 2>/dev/null" || echo "throttled=unknown")
    if echo "$THROTTLE" | grep -q "throttled=0x0"; then
        log_pass "No throttling detected"
    elif [ "$THROTTLE" != "throttled=unknown" ]; then
        log_warn "Throttling detected: $THROTTLE"
    fi
}

# Generate summary report
generate_report() {
    echo ""
    echo "========================================="
    echo "Validation Summary"
    echo "========================================="
    echo -e "${GREEN}Passed:${NC} $PASS_COUNT"
    echo -e "${YELLOW}Warnings:${NC} $WARN_COUNT"
    echo -e "${RED}Failed:${NC} $FAIL_COUNT"
    echo ""
    
    if [ "$FAIL_COUNT" -eq 0 ]; then
        if [ "$WARN_COUNT" -eq 0 ]; then
            log_info "Cluster is healthy! ✅"
        else
            log_info "Cluster is operational with warnings ⚠️"
        fi
    else
        log_info "Cluster has issues that need attention ❌"
    fi
    
    # Save report
    REPORT_FILE="validation-report-$(date +%Y%m%d_%H%M%S).txt"
    {
        echo "k0s Cluster Validation Report"
        echo "Generated: $(date)"
        echo "Host: mctv3.local"
        echo ""
        echo "Results:"
        echo "  Passed: $PASS_COUNT"
        echo "  Warnings: $WARN_COUNT"
        echo "  Failed: $FAIL_COUNT"
    } > "$REPORT_FILE"
    
    echo ""
    echo "Report saved to: $REPORT_FILE"
}

# Quick health check
quick_check() {
    check_ssh || return 1
    
    # Quick k0s status
    STATUS=$(ssh -i ~/.ssh/momscloset alan@mctv3.local "sudo k0s status 2>/dev/null" || echo "Not running")
    echo "k0s status: $STATUS"
    
    # Quick node check
    if [ -f kubeconfig.yaml ] && command -v kubectl &> /dev/null; then
        export KUBECONFIG=$(pwd)/kubeconfig.yaml
        kubectl get nodes 2>/dev/null || echo "Cannot get node status"
    fi
}

# Main menu
show_menu() {
    echo ""
    echo "========================================="
    echo "k0s Cluster Validation Tool"
    echo "========================================="
    echo "1. Full validation"
    echo "2. Quick health check"
    echo "3. System check only"
    echo "4. Cluster check only"
    echo "5. Network check only"
    echo "6. Performance check only"
    echo "7. Exit"
    echo ""
    echo -n "Select an option: "
}

# Handle command line arguments
if [ "$1" = "quick" ]; then
    quick_check
    exit 0
fi

# Main execution
main() {
    while true; do
        show_menu
        read -r option
        
        PASS_COUNT=0
        FAIL_COUNT=0
        WARN_COUNT=0
        
        case $option in
            1)
                check_ssh
                check_pi_system
                check_k0s_install
                check_cluster
                check_network
                check_performance
                generate_report
                ;;
            2)
                quick_check
                ;;
            3)
                check_ssh
                check_pi_system
                generate_report
                ;;
            4)
                check_cluster
                generate_report
                ;;
            5)
                check_network
                generate_report
                ;;
            6)
                check_ssh
                check_performance
                generate_report
                ;;
            7)
                exit 0
                ;;
            *)
                echo "Invalid option"
                ;;
        esac
    done
}

main "$@"