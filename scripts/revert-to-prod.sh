#!/bin/bash
# Revert mctv3 from lab (10.0.1.16) back to prod location (192.168.12.149)
# Run this script when moving the node back to production

set -e

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}MCTV3 Lab → Prod Revert Script${NC}"
echo "========================================"
echo ""
echo "This will:"
echo "  1. Update k0s config to use prod IP (192.168.12.149)"
echo "  2. Restart k0s controller"
echo "  3. Update local kubeconfig"
echo ""
echo -e "${YELLOW}Prerequisites:${NC}"
echo "  - Node physically moved back to prod location"
echo "  - Node has static IP 192.168.12.149 configured"
echo "  - SSH access working"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Configuration
PROD_IP="192.168.12.149"
LAB_IP="10.0.1.16"
SSH_KEY="$HOME/.ssh/momscloset"
SSH_USER="alan"
PROD_CONFIG="/tmp/k0s-prod-config.yaml"
PROD_KUBECONFIG="$HOME/.kube/clusters/mctv3-prod.yaml.bak"

echo ""
echo -e "${GREEN}Step 1: Verify prod k0s config backup exists${NC}"
if [ ! -f "$PROD_CONFIG" ]; then
    echo -e "${RED}ERROR: Prod config not found at $PROD_CONFIG${NC}"
    echo "Expected content:"
    cat <<'EOF'
apiVersion: k0s.k0sproject.io/v1beta1
kind: ClusterConfig
metadata:
  name: k0s
spec:
  api:
    address: 192.168.12.149
    sans:
    - mctv3.lan
    - mctv3.local
    - 192.168.12.149
  storage:
    etcd:
      peerAddress: 192.168.12.149
EOF
    exit 1
fi

echo "✓ Found prod config"
cat "$PROD_CONFIG"

echo ""
echo -e "${GREEN}Step 2: Copy prod config to node${NC}"
scp -i "$SSH_KEY" "$PROD_CONFIG" ${SSH_USER}@${PROD_IP}:/tmp/k0s-prod.yaml
ssh -i "$SSH_KEY" ${SSH_USER}@${PROD_IP} "sudo cp /tmp/k0s-prod.yaml /etc/k0s/k0s.yaml && sudo chown root:root /etc/k0s/k0s.yaml && sudo chmod 600 /etc/k0s/k0s.yaml"
echo "✓ Config deployed"

echo ""
echo -e "${GREEN}Step 3: Restart k0s controller${NC}"
ssh -i "$SSH_KEY" ${SSH_USER}@${PROD_IP} "sudo systemctl restart k0scontroller"
echo "✓ Restarting k0s..."
sleep 30

echo ""
echo -e "${GREEN}Step 4: Verify k0s is running${NC}"
ssh -i "$SSH_KEY" ${SSH_USER}@${PROD_IP} "sudo systemctl status k0scontroller --no-pager | head -10"

echo ""
echo -e "${GREEN}Step 5: Update local kubeconfig${NC}"

# Check if prod kubeconfig backup exists
if [ -f "$PROD_KUBECONFIG" ]; then
    echo "Restoring from backup: $PROD_KUBECONFIG"
    cp "$PROD_KUBECONFIG" "$HOME/.kube/clusters/mctv3.yaml"
else
    echo "No backup found, creating new kubeconfig"
    # Fetch new kubeconfig from node
    ssh -i "$SSH_KEY" ${SSH_USER}@${PROD_IP} "sudo cat /var/lib/k0s/pki/admin.conf" > "$HOME/.kube/clusters/mctv3.yaml"
fi

# Verify server IP
SERVER_IP=$(grep "server:" "$HOME/.kube/clusters/mctv3.yaml" | awk '{print $2}')
echo "Kubeconfig server: $SERVER_IP"

if [[ "$SERVER_IP" != *"$PROD_IP"* ]]; then
    echo -e "${YELLOW}WARNING: Kubeconfig has unexpected server IP${NC}"
    echo "Updating to prod IP..."
    sed -i.bak "s|server: https://.*:6443|server: https://$PROD_IP:6443|g" "$HOME/.kube/clusters/mctv3.yaml"
fi

echo ""
echo -e "${GREEN}Step 6: Test cluster connectivity${NC}"
kubectl --kubeconfig="$HOME/.kube/clusters/mctv3.yaml" get nodes

echo ""
echo -e "${GREEN}✓ Revert complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Verify all pods are running: kubectl get pods -A"
echo "  2. Check Frigate is recording"
echo "  3. Test Cloudflare tunnel access"
echo "  4. Archive lab kubeconfig: mv ~/.kube/clusters/mctv4-lab.yaml ~/.kube/clusters/archive/"
echo ""
echo "To use this cluster:"
echo "  export KUBECONFIG=$HOME/.kube/clusters/mctv3.yaml"
