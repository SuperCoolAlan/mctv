# Fixes Applied for Fresh Installation

## 1. Control-Plane Taint Issue ✅
**Fixed in multiple places:**
- Added `workerProfiles` to `cluster.yaml` to prevent taint
- Added taint removal in `deploy.sh` after cluster deployment
- Added taint removal in `deploy-dynamic.sh` after cluster deployment

## 2. WiFi Configuration ✅
**Already fixed in INSTALL.sh:**
- WiFi configuration runs FIRST in phase1_pi_setup()
- Ensures Pi stays connected after reboot

## 3. Confirmation Prompts ✅
**Already handled:**
- `INSTALL.sh` supports `-y` flag for auto mode
- `setup-remote.sh` supports `-y` flag and passes it to pi5-k0s-setup-auto.sh
- `deploy-dynamic.sh` has no interactive prompts

## 4. NVMe Support ✅
**Already integrated:**
- `pi5-k0s-setup-auto.sh` includes full NVMe support with:
  - PCIe enablement via dtparam=pciex1
  - NVMe formatting and mounting
  - k0s data directory on NVMe
- `deploy-dynamic.sh` checks and prepares NVMe storage

## 5. SOPS/KSOPS Issue ✅
**Not a real issue:**
- User typed GPG password incorrectly
- KSOPS works fine when GPG key is properly unlocked

## Ready for Fresh Install

The installation can now be run in fully automated mode:
```bash
cd /Users/alan/Documents/mctv
./INSTALL.sh -y
```

This will:
1. Configure WiFi on the Pi
2. Setup NVMe storage
3. Deploy k0s without control-plane taint
4. Deploy all services (local-path-provisioner, Cloudflare tunnel, Frigate, Twingate)
5. All without any manual intervention