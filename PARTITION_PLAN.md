# NVMe Partitioning Plan for MCTV3

**Date:** 2025-10-26
**Status:** Ready to execute when back at prod location

## Problem Summary
- Frigate CCTV recordings filled root partition (374GB/468GB = 85%)
- Triggered disk pressure on Oct 19, 2025 @ 1:19 AM
- Caused 7 days of pod failures and cluster instability
- Fixed temporarily by deleting old recordings (freed 345GB)

## Current NVMe Layout
```
/dev/nvme0n1: 512GB total (476.9GB usable)
├── /dev/nvme0n1p1: 512MB  (boot/firmware - FAT32)
└── /dev/nvme0n1p2: 476.4GB (root filesystem - ext4)
```

## Current Usage (Post-Cleanup)
- Total used: 30GB (7%)
- k0s + containerd: 12GB
- System files: 1.7GB
- Frigate recordings: 772MB (with 7-day retention)

## Proposed Layout: Option 1 (Conservative - RECOMMENDED)
```
/dev/nvme0n1p1:   512MB  (boot/firmware) [UNCHANGED]
/dev/nvme0n1p2:   100GB  (root OS + k0s) [SHRINK FROM 476.4GB]
/dev/nvme0n1p3:   376GB  (dedicated CCTV) [NEW PARTITION]
```

### Rationale
- Root partition: 100GB provides 5x headroom over 20GB actual needs
- CCTV partition: 376GB isolated = ~53 days at 7GB/day
- If CCTV fills up, it won't kill the cluster

## Execution Steps (Requires Physical Access)

### Prerequisites
- SD card with Raspberry Pi OS (to boot from while resizing)
- Physical access to mctv3
- Backup of k0s config: `/tmp/k0s-prod-config.yaml`
- Backup kubeconfig: `~/.kube/clusters/mctv3-prod.yaml.bak`

### Step 1: Boot from SD Card
1. Insert SD card with Raspberry Pi OS
2. Configure Pi to boot from SD (not NVMe)
3. Reboot into SD card OS

### Step 2: Resize Partitions
```bash
# WARNING: This is destructive if done wrong!
# Backup data first if possible

# Install tools
sudo apt update && sudo apt install -y parted

# Check current layout
sudo parted /dev/nvme0n1 print

# Resize partition 2 from 476.4GB to 100GB
sudo parted /dev/nvme0n1 resizepart 2 100GB

# Resize the filesystem
sudo e2fsck -f /dev/nvme0n1p2
sudo resize2fs /dev/nvme0n1p2

# Create new partition 3 for CCTV
sudo parted /dev/nvme0n1 mkpart primary ext4 100GB 100%

# Format new partition
sudo mkfs.ext4 -L cctv /dev/nvme0n1p3
```

### Step 3: Update fstab
```bash
# Mount the root partition
sudo mkdir -p /mnt/nvme-root
sudo mount /dev/nvme0n1p2 /mnt/nvme-root

# Edit fstab
sudo nano /mnt/nvme-root/etc/fstab

# Add this line:
# LABEL=cctv    /mnt/cctv    ext4    defaults,nofail    0    2

# Create mount point
sudo mkdir -p /mnt/nvme-root/mnt/cctv
```

### Step 4: Migrate OpenEBS Data
```bash
# Mount CCTV partition
sudo mkdir -p /mnt/cctv
sudo mount /dev/nvme0n1p3 /mnt/cctv

# Move existing data
sudo mv /mnt/nvme-root/var/openebs /mnt/cctv/openebs

# Create symlink (or update OpenEBS config)
sudo ln -s /mnt/cctv/openebs /mnt/nvme-root/var/openebs
```

### Step 5: Reboot from NVMe
1. Remove SD card
2. Reboot
3. Verify partitions: `df -h`
4. Verify k0s: `kubectl get nodes`
5. Verify Frigate can write to new partition

## Alternative: Update OpenEBS StorageClass

Instead of symlink, update OpenEBS local provisioner to use `/mnt/cctv/openebs`:

```yaml
# In openebs-storage manifests
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: openebs-hostpath
provisioner: openebs.io/local
parameters:
  BasePath: "/mnt/cctv/openebs"  # Changed from /var/openebs/local
```

## Rollback Plan

If something goes wrong:
1. Boot from SD card
2. Extend nvme0n1p2 back to full size
3. Delete nvme0n1p3
4. Restore from backup

## Network Configuration Notes

**Lab location (current):**
- IP: 10.0.1.16
- Context: mctv4-lab
- Kubeconfig: `~/.kube/clusters/mctv4-lab.yaml`

**Prod location:**
- IP: 192.168.12.149
- Context: k0s
- Kubeconfig: Restore from `~/.kube/clusters/mctv3-prod.yaml.bak`
- k0s config: Restore from `/tmp/k0s-prod-config.yaml`

## Post-Partition Actions

1. Update Frigate retention to match new capacity
2. Set up monitoring for `/mnt/cctv` disk usage
3. Configure alert if CCTV partition reaches 80%
4. Test disk pressure taint doesn't reappear

## Safety Notes

⚠️ **IMPORTANT:**
- This operation is DESTRUCTIVE to partition table
- Backup anything important before proceeding
- Do NOT run these commands on a running system
- MUST boot from SD card to resize NVMe partitions safely
- Test in lab before doing at prod location
