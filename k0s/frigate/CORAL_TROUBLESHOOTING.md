# Coral USB Troubleshooting

## Current Status

The Coral USB TPU is not currently detected by the Raspberry Pi. The device was briefly detected (idVendor=18d1, idProduct=9302) but then disconnected.

## Issues Found

1. **USB Disconnection**: dmesg logs show:
   ```
   usb 2-1: New USB device found, idVendor=18d1, idProduct=9302
   usb 2-1: USB disconnect, device number 7
   ```

2. **Power Issues**: The Coral USB can draw up to 900mA, which may exceed the Raspberry Pi's USB power capacity.

## Recommended Solutions

### Option 1: Powered USB Hub (Recommended)
Connect the Coral USB through a powered USB 3.0 hub to ensure adequate power delivery.

### Option 2: Check Physical Connection
1. Unplug the Coral USB device
2. Wait 10 seconds
3. Plug it back in firmly
4. Check dmesg: `dmesg | grep -E "(usb|coral|18d1)"`

### Option 3: USB Port Selection
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