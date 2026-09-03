# iOS 18 Background Video Recording Fix

## Problem

On iOS 18, Apple has tightened restrictions on multitasking camera access when running from SpringBoard. The `AVCaptureSession.multitaskingCameraAccessEnabled` property may not be sufficient when the capture session runs in SpringBoard's process, especially when the device is locked or other apps are in the foreground.

## Solution

The video recording now runs in a **dedicated service process** (`JWRRecorderApp --service`) launched via LaunchDaemon. This process has:

1. Proper multitasking camera access entitlements
2. Isolated from SpringBoard's lifecycle management
3. Persistent background execution via `KeepAlive`

## Changes Made

### 1. Service Process (`app/main.m`)
- Added full video notification handling (`toggleVideo`, `startVideo`, `stopVideo`)
- Pre-initializes `AVAudioSession` for background audio
- Logs multitasking camera access support at startup
- Creates `.jwr-service-ready` flag file when ready

### 2. Entitlements (`app/JWRRecorderApp.entitlements`)
- Added `com.apple.private.security.no-container` for full filesystem access
- Kept `com.apple.developer.avfoundation.multitasking-camera-access`
- Kept `com.apple.private.avfoundation.capture.nonstandard-client`

### 3. LaunchDaemon (`layout/Library/LaunchDaemons/com.jimwas.recorder.service.plist`)
- Enhanced `KeepAlive` with `SuccessfulExit` and `Crashed` recovery
- Added `WorkingDirectory` and `EnvironmentVariables` for proper PATH
- Logs to `/tmp/jwr-service.log` and `/tmp/jwr-service-error.log`

### 4. Makefile
- Changed app install path to `/var/jb/Applications` (rootless jailbreak standard)
- Updated `after-install` to properly reload the LaunchDaemon

### 5. Tweak.xm
- SpringBoard now checks for service availability via `[JWRRecorderManager serviceProcessAvailable]`
- Video notifications are forwarded to the service process when available
- Falls back to SpringBoard recording if service is unavailable

## Usage

### After Installing

1. **Reboot userspace** or run:
   ```bash
   launchctl bootout system/com.jimwas.recorder.service 2>/dev/null || launchctl unload -w /var/jb/Library/LaunchDaemons/com.jimwas.recorder.service.plist 2>/dev/null || true
   launchctl bootstrap system /var/jb/Library/LaunchDaemons/com.jimwas.recorder.service.plist 2>/dev/null || launchctl load -w /var/jb/Library/LaunchDaemons/com.jimwas.recorder.service.plist
   ```

2. **Verify service is running**:
   ```bash
   ps aux | grep JWRRecorderApp
   cat /var/mobile/Documents/.jwr-service-ready  # should exist
   tail -f /tmp/jwr-service.log  # check for "service ready"
   ```

3. **Test background recording**:
   - Lock your device
   - Use volume buttons to start recording
   - Unlock and open another app
   - Check `/tmp/jwr-service.log` for recording status

### Manual Service Control

```bash
# Start service
launchctl bootstrap system /var/jb/Library/LaunchDaemons/com.jimwas.recorder.service.plist

# Stop service
launchctl bootout system/com.jimwas.recorder.service

# Check status
launchctl list | grep jwr

# View logs
tail -f /tmp/jwr-service.log
tail -f /tmp/jwr-service-error.log
```

### iOS 18 Control Center & Lock Screen Controls

Because iOS 18 replaced legacy `ControlCenterUIKit` with WidgetKit-based controls, `JWRRecorderApp` supports native URL schemes that can be added directly to the iOS 18 Control Center, Lock Screen, or Action Button:

* `jwr://video` - Toggle video recording
* `jwr://video/start` - Start video recording
* `jwr://video/stop` - Stop video recording
* `jwr://audio` - Toggle audio recording
* `jwr://photo` - Capture photo

**How to add to iOS 18 Control Center:**
1. Open the Apple **Shortcuts** app and create a shortcut named "Toggle Video" with action **Open URL** -> `jwr://video`.
2. Swipe down to open the iOS 18 **Control Center**, tap **+** to edit, and tap **Add a Control**.
3. Choose **Shortcuts** -> select your "Toggle Video" shortcut.

### Trigger Recording from Anywhere

```bash
# Via notify_post (from another app or script)
notify_post "com.jimwas.recorder/toggleVideo"
notify_post "com.jimwas.recorder/startVideo"
notify_post "com.jimwas.recorder/stopVideo"

# Via JWRRecorderApp helper
/var/jb/Applications/JWRRecorderApp.app/JWRRecorderApp --post-video
```

## Debugging

### Check Service Logs
```bash
cat /tmp/jwr-service.log
cat /tmp/jwr-service-error.log
```

### Check Multitasking Camera Support
Look for these lines in the service log:
```
AVCaptureSession class available in service: 1
multitaskingCameraAccessSupported: 1
multitaskingCameraAccessEnabled set to: 1
```

### Check SpringBoard Logs
```bash
log show --predicate 'process == "SpringBoard"' --last 5m | grep -i "jimwas\|recorder"
```

### Verify Entitlements
```bash
/usr/bin/security -v find-entitlements /var/jb/Applications/JWRRecorderApp.app/JWRRecorderApp
```

## Fallback Behavior

If the service process is not available (file `/var/mobile/Documents/.jwr-service-ready` doesn't exist), video recording falls back to SpringBoard with the original multitasking camera hooks. This ensures the tweak still works even if the service fails to start.

## Known Limitations

1. **First recording after boot** may take 2-3 seconds as the service initializes
2. **Audio routing** may need manual adjustment in Control Center for speaker output
3. **Camera switch** during recording requires stopping and restarting

## Future Improvements

- Add IPC for real-time status queries from SpringBoard
- Implement automatic service health checks
- Add preference to force SpringBoard mode for debugging
- Consider mediaserverd hooking for even more stable background access
