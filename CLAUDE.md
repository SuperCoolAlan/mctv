# MCTV K0s Cluster Documentation

## Kubernetes Context

This repository deploys to the **mctv3** cluster:
```bash
export KUBECONFIG=~/.kube/clusters/mctv3.yaml
```

## Secrets Management

### Encryption
All secrets in this repository are encrypted using SOPS with GPG:
- GPG Key: `29FE211C0F0BF17C10EFEB150ECC79FC3C76B242`
- Files are saved with `.enc.yaml` extension in `secrets/` directories

### Encrypting a new secret
```bash
# Create your secret file
cat > secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
  namespace: my-namespace
type: Opaque
stringData:
  key: value
EOF

# Encrypt it
sops --encrypt --pgp 29FE211C0F0BF17C10EFEB150ECC79FC3C76B242 secret.yaml > secrets/my-secret.enc.yaml

# Remove the unencrypted file
rm secret.yaml
```

### Working with encrypted secrets
```bash
# Decrypt to view
sops --decrypt secrets/my-secret.enc.yaml

# Edit in place
sops secrets/my-secret.enc.yaml

# Apply to cluster
kustomize build --enable-exec --enable-alpha-plugins . | kubectl apply -f -
```

### KSOPS Integration
Each service uses a `secrets-generator.yaml` for KSOPS:
```yaml
apiVersion: viaduct.ai/v1
kind: ksops
metadata:
  name: service-secret-generator
  annotations:
    config.kubernetes.io/function: |
      exec:
        path: ksops
files:
  - secrets/secret-name.enc.yaml
```

## Deployment Commands

All deployments use Kustomize with KSOPS:
```bash
# Set context
export KUBECONFIG=~/.kube/clusters/mctv3.yaml

# Deploy
kustomize build --enable-exec --enable-alpha-plugins . | kubectl apply -f -

# Preview
kustomize build --enable-exec --enable-alpha-plugins .
```

## Services

- **Cloudflare Tunnel**: Exposes cluster services securely
- **Frigate**: NVR system with camera recording
- **Twingate**: Zero-trust network access