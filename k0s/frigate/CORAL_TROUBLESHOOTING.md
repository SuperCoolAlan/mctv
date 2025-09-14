# Coral USB Troubleshooting

## Current Status

The Coral USB TPU is not currently detected by the Raspberry Pi. The device was briefly detected (idVendor=18d1, idProduct=9302) but then disconnected.

## Issues Found

1. **USB Disconnection**: dmesg logs show:
   ```
   usb 2-1: New USB device found, idVendor=18d1, idProduct=9302
   usb 2-1: USB disconnect, device number 7
   ```

2. **Power Issues**: The Coral USB power consumption varies by runtime:
   - **Maximum frequency (libedgetpu1-max)**: ~4W (up to 900mA at 5V)
   - **Reduced frequency (libedgetpu1-std)**: ~2W (up to 500mA at 5V)
   
   The Raspberry Pi may struggle to provide adequate power, especially at maximum frequency.

## Recommended Solutions

### Option 1: Check Edge TPU Runtime Frequency
The Coral may be running at maximum frequency (4W power draw). Switch to reduced frequency:
```bash
# Check current runtime
dpkg -l | grep libedgetpu

# If libedgetpu1-max is installed, switch to standard (reduced frequency)
sudo apt-get remove libedgetpu1-max
sudo apt-get install libedgetpu1-std
```

### Option 2: Powered USB Hub (Recommended)
Connect the Coral USB through a powered USB 3.0 hub to ensure adequate power delivery, especially if running at maximum frequency.

### Option 3: Check Physical Connection
1. Unplug the Coral USB device
2. Wait 10 seconds
3. Plug it back in firmly
4. Check dmesg: `dmesg | grep -E "(usb|coral|18d1)"`

### Option 4: USB Port Selection
Try different USB ports on the Raspberry Pi. USB 3.0 ports (blue) typically provide more power.

## Verification Steps

Once the Coral is connected:

1. Verify detection:
   ```bash
   lsusb | grep -E "(Google|Coral|18d1|1a6e)"
   ```

2. Check device permissions:
   ```bash
   ls -la /dev/bus/usb/*/
   ```

3. Re-enable Coral in Frigate:
   - Uncomment the coral detector in `values-override.yaml`
   - Uncomment the model configuration
   - Redeploy: `kustomize build --enable-exec --enable-alpha-plugins . | kubectl apply -f -`

## Configuration When Working

```yaml
detectors:
  coral:
    type: edgetpu
    device: usb
  cpu1:
    type: cpu
    num_threads: 2

model:
  path: /edgetpu_model.tflite
  width: 320
  height: 320
```