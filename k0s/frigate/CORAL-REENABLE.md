# Frigate Coral TPU Re-enablement Guide

## Current Status (2025-10-17)

**Detector Status**: DISABLED
**Reason**: Raspberry Pi 5 overheating (reached 85.1°C, thermal shutdown threshold)
**Recording Status**: ACTIVE (motion-based recording working)

### Temperature History
- With CPU detector: 76.8°C → 85.1°C (thermal throttling + shutdown risk)
- Coral USB disappeared due to heat/power issues
- Throttling flags: `0xe0006` (active throttling occurring)

### What's Currently Working
- ✅ Live camera feed
- ✅ Continuous recording (22 days retention)
- ✅ Motion-based event recording (30 day retention)
- ✅ Audio recording
- ✅ Playback and snapshots
- ✅ FPS limiting (fixed to prevent "exceeded fps limit" errors)

### What's Disabled
- ❌ Object detection (person, car, etc.)
- ❌ Smart filtering by object type
- ❌ Coral EdgeTPU acceleration

## Hardware Ordered
- **Cooling fan + thermal unit** (awaiting delivery)

## Re-enablement Steps

### 1. Install Cooling Solution
```bash
# After physical installation, verify temperature is stable
ssh mctv3.lan "vcgencmd measure_temp && vcgencmd get_throttled"
```

Target: Temperature should be <70°C at idle, <75°C under load

### 2. Connect and Verify Coral USB

```bash
# Plug in Coral USB device, wait 10 seconds

# Verify Coral is detected (should show ID 1a6e:089a or 18d1:9302)
ssh mctv3.lan "lsusb | grep -E '1a6e|18d1'"

# Verify USB autosuspend is disabled (should show "on")
ssh mctv3.lan "cat /sys/bus/usb/devices/*/power/control | head -1"
```

**Expected output:**
- Bus 002 Device 002: ID 1a6e:089a (bootloader) or 18d1:9302 (runtime)
- Power control: `on`

### 3. Re-enable Coral Detector in Config

Edit `values-override.yaml`:

```yaml
# Object detection configuration
detectors:
  # Coral EdgeTPU USB accelerator for efficient object detection
  coral:
    type: edgetpu
    device: usb

# Model optimized for EdgeTPU
model:
  path: /edgetpu_model.tflite
  width: 320
  height: 320
```

And:
```yaml
cameras:
  mctv:
    detect:
      enabled: true  # Re-enable detection
      width: 1920
      height: 1080
      fps: 5
```

### 4. Deploy Updated Configuration

```bash
cd /Users/alan/Documents/mctv/k0s/frigate
kustomize build --enable-exec --enable-alpha-plugins . | KUBECONFIG=~/.kube/clusters/mctv3.yaml kubectl apply -f -
```

### 5. Monitor Startup

```bash
# Watch pod restart
KUBECONFIG=~/.kube/clusters/mctv3.yaml kubectl get pods -n frigate -w

# Wait for pod to be Running, then check logs for Coral detection
KUBECONFIG=~/.kube/clusters/mctv3.yaml kubectl logs -n frigate -l app.kubernetes.io/name=frigate --tail=50 | grep -i coral
```

**Expected log output:**
```
[INFO] detector.coral: Starting detection process
```

### 6. Monitor Temperature Under Load

```bash
# Check temperature after 5 minutes of operation
ssh mctv3.lan "vcgencmd measure_temp && vcgencmd get_throttled"
```

**Target:**
- Temperature: <75°C
- Throttled: `0x0` (no throttling) or `0xe0000` (historical only, not current)

### 7. Verify Detection is Working

Check the Frigate UI at your Cloudflare tunnel URL:
- Live view should show detection boxes
- Events should show classified objects (person, car, etc.)

## Troubleshooting

### If Coral Not Detected
```bash
# Check dmesg for USB errors
ssh mctv3.lan "dmesg | tail -50 | grep -i usb"

# Verify udev rule is present
ssh mctv3.lan "cat /etc/udev/rules.d/99-coral-usb.rules"

# Reload udev rules
ssh mctv3.lan "sudo udevadm control --reload-rules && sudo udevadm trigger"

# Unplug/replug Coral USB
```

### If Still Overheating
- Verify fan is powered and spinning
- Check airflow around Raspberry Pi
- Consider reducing detection FPS to 3 (from 5)
- Monitor with: `watch -n 5 'vcgencmd measure_temp'`

### If Watchdog Switches to CPU
The watchdog will automatically switch to CPU detector if it detects 3 consecutive Coral failures. If this happens:
1. Check temperature (likely overheating again)
2. Check `lsusb` for Coral presence
3. Fix underlying issue (cooling, USB power)
4. Manually redeploy with Coral config

## Configuration Files Modified

- `values-override.yaml`: Added FPS limiting to ffmpeg inputs, detector configuration
- `resources/frigate-watchdog-configmap.yaml`: Watchdog that auto-switches to CPU on Coral failure
- `resources/frigate-watchdog-deployment.yaml`: Watchdog deployment
- `resources/frigate-watchdog-rbac.yaml`: Permissions for watchdog
- `/etc/udev/rules.d/99-coral-usb.rules` (on mctv3.lan host): Disables USB autosuspend

## Git Branch
Current work is on branch: `rollback-usbcoral-detector-to-cpu`

## Notes
- The FPS limit fix (`-r 5` in ffmpeg input_args) prevents "exceeded fps limit" errors
- USB autosuspend was causing Coral to disappear after 2 seconds (fixed with udev rule)
- CPU detection generates 10-15°C more heat than Coral detection
- Raspberry Pi 5 throttles at 80°C, shuts down at 85°C
