# Local Path Provisioner

This deploys the Rancher Local Path Provisioner to provide persistent storage for single-node k0s clusters.

## What it does

- Creates a StorageClass named `local-path` that provisions PersistentVolumes on the local filesystem
- Sets this StorageClass as the default for the cluster
- Stores data in `/opt/local-path-provisioner` on the host

## Deployment

```bash
export KUBECONFIG=~/.kube/clusters/mctv3.yaml
kustomize build . | kubectl apply -f -
```

## Verify

```bash
kubectl get storageclass
kubectl get pods -n local-path-storage
```

The `local-path` StorageClass should show `(default)` next to its name.