# JimWas Recorder Developer Documentation

This document describes the version 1.9.3 implementation. It is intended to
help a future developer debug, extend, package, and safely recover the tweak
without rediscovering its process boundaries or state assumptions.

## Required jailbreak packages

The tested iOS 16.3 Dopamine configuration requires all of the following:

- ElleKit or compatible tweak injection.
- PreferenceLoader.
- **Legacy arm64e Support**, Debian package `oldabi`, version 2.0.1 or newer.

`oldabi` is a runtime requirement, not merely a build dependency. Without it,
the arm64e tweak can partially inject: SpringBoard hooks and diagnostic messages
may appear while camera capture and physical feedback still fail. That symptom
can be mistaken for an AVFoundation permission or process-ownership problem.
Always verify this dependency before changing capture architecture:

```sh
dpkg-query -W oldabi
```

The package `control` file declares `oldabi (>= 2.0.1)` so normal package-manager
installation enforces the requirement.

## Design goals

JimWas Recorder is optimized for low-attention, resilient capture:

1. A user action should reach the recorder without requiring the companion app
   to be open.
2. A video file should be finalized before a replacement segment begins.
3. The system should distinguish the user's requested recording state from the
   current AVFoundation state.
4. Camera/media-service interruptions should produce feedback and an automatic
   recovery attempt.
5. The screen should be allowed to remain dark during an active video.
6. Unsupported camera options should not be shown or trusted.
7. Privacy indicators remain enabled and call audio is not captured.

## Process architecture

The package contains four cooperating runtime surfaces.

### SpringBoard tweak

Files: `Tweak.xm`, `JWRRecorderManager.m`, `JWRPreferences.m`, and
`JWRLogger.m`.

SpringBoard owns:

- Volume-button trigger detection.
- Video capture and photo capture.
- Raise-to-wake and tap-to-wake suppression while video is active.
- Haptic and vibration playback.
- Video/photo Darwin notification receivers.
- Preference reload handling.
- Startup scanning of staged videos.

Video capture intentionally runs inside SpringBoard. Earlier attempts to run
the camera from the launch service were interrupted with
`AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableInBackground`.
Moving the session into the injected SpringBoard process made locked-screen and
background capture viable on the tested iOS 16.3 devices.

This is the highest-risk architectural choice in the project. A crash in tweak
code can crash SpringBoard. Keep all recorder work serialized, avoid blocking
the main thread, and test every lifecycle change with SSH available.

### Companion application

Files: `app/main.m` and `app/JWRAppDelegate.m`.

When launched normally, `JWRRecorderApp` displays permission state and requests:

- Camera access.
- Microphone access.
- Photos add access.
- Always Location access.

The companion application does not need to remain open for recording.

### Launch service

The same executable runs with `--service` from:

```text
/var/jb/Library/LaunchDaemons/com.jimwas.recorder.service.plist
```

The launch daemon runs as `mobile`, has `RunAtLoad` and `KeepAlive` enabled, and
keeps a Core Foundation run loop alive. It owns:

- Audio-only recording.
- The audio-toggle Darwin notification receiver.
- The iOS 18 camera-host launch relay (see [iOS 18 camera host launch
  relay](#ios-18-camera-host-launch-relay)).
- Background location caching.
- Preference reload handling for the service process.

It writes `/var/mobile/Documents/.jwr-service-ready` at startup as a lightweight
readiness marker.

### Preference and Control Center bundles

The preference bundle builds Settings rows programmatically from
`prefs/Resources/Root.plist`. Picker-style values use action sheets instead of
`PSListItemsController`; this avoids crashes encountered with list-item
controllers on the target firmware.

The video Control Center module posts `JWRNotifyTriggerVideo` and the audio
module posts `JWRNotifyTriggerAudio` on every firmware, so both toggles pass
through SpringBoard's shared `Enabled`/lock gate before reaching the recorder
(the iOS 18 relay still foregrounds the companion app first; see [iOS 18
camera host launch relay](#ios-18-camera-host-launch-relay)). Both modules
subscribe to `JWRNotifyState`, which carries a video/audio active bitmask, and
keep their selected appearance in sync with the actual recorder state instead
of reporting a cosmetic self-state.

## Event routing

Darwin notifications are used because the sender and receiver may live in
different processes.

| Constant | Notification string | Sender | Receiver |
| --- | --- | --- | --- |
| `JWRNotifyVideo` | `com.jimwas.recorder/toggleVideo` | Hardware trigger, helper CLI mode (all iOS 16 path) | SpringBoard |
| `JWRNotifyTriggerVideo` | `com.jimwas.recorder/triggerVideo` | Video CC module and helper CLI mode; hardware-independent diagnostics | SpringBoard |
| `JWRNotifyTriggerAudio` | `com.jimwas.recorder/triggerAudio` | Audio CC module | SpringBoard |
| `JWRNotifyLaunchCameraVideo` | `com.jimwas.recorder/launchCameraVideo` | SpringBoard iOS 18 host-launch relay | Launch service |
| `JWRNotifyLaunchCameraPhoto` | `com.jimwas.recorder/launchCameraPhoto` | SpringBoard iOS 18 host-launch relay | Launch service |
| `JWRNotifyForegroundVideo` | `com.jimwas.recorder/foregroundVideo` | Launch service host-launch relay, helper CLI mode | Companion app |
| `JWRNotifyForegroundPhoto` | `com.jimwas.recorder/foregroundPhoto` | Launch service host-launch relay, helper CLI mode | Companion app |
| `JWRNotifyAudio` | `com.jimwas.recorder/toggleAudio` | Hardware trigger, helper CLI mode | Launch service |
| `JWRNotifyPhoto` | `com.jimwas.recorder/takePhoto` | Hardware trigger, helper CLI mode (iOS 16 path) | SpringBoard |
| `JWRNotifyReload` | `com.jimwas.recorder/reload` | Preferences | SpringBoard and launch service |
| `JWRNotifyState` | `com.jimwas.recorder/stateChanged` | Recorder manager (video/audio active bitmask) | Control Center modules |
| `JWRNotifyHapticStarted` | `com.jimwas.recorder/hapticStarted` | Audio recorder | SpringBoard |
| `JWRNotifyHapticStopped` | `com.jimwas.recorder/hapticStopped` | Audio recorder | SpringBoard |
| `JWRNotifyHapticPhoto` | `com.jimwas.recorder/hapticPhoto` | Photo delegate | SpringBoard |
| `JWRNotifyHapticHeartbeat` | `com.jimwas.recorder/hapticHeartbeat` | Healthy recorder timer | SpringBoard |
| `JWRNotifyHapticFailure` | `com.jimwas.recorder/hapticFailure` | Recorder failure path | SpringBoard |
| `JWRNotifyHapticVideoStarted` | `com.jimwas.recorder/hapticVideoStarted` | Video start path | SpringBoard |
| `JWRNotifyHapticVideoStopped` | `com.jimwas.recorder/hapticVideoStopped` | Video finalization path | SpringBoard |

`JWRRecorderApp` also supports one-shot helper modes:

```text
--post-video
--post-audio
--post-photo
--post-foreground-video
--post-foreground-photo
--trigger-video
--service
```

The post modes deliver the corresponding Darwin notification and exit;
`--trigger-video` runs the full SpringBoard trigger path, including the
iOS 18 companion-app foreground launch.

### iOS 18 camera host launch relay

On iOS 18, video and photo triggers must foreground the companion app because
SpringBoard can no longer hold the camera in the background. The obvious
implementation — calling `LSApplicationWorkspace openApplicationWithBundleID:`
from SpringBoard — has two hard constraints discovered on iOS 18.1.1:

- The API silently refuses off-main-thread callers: it returns `NO` in ~20ms
  with no error and no launch, regardless of process.
- Called on SpringBoard's main thread it works, but blocks that thread for
  ~10 seconds during a cold launch — freezing the entire UI. There is no
  async variant on this firmware (`openApplicationWithBundleID:options:withResult:`
  and `openApplicationWithBundleID:configuration:completionHandler:` are both
  absent).

The fix is a launch relay through the always-running launch service. The same
API called from the service's main thread takes ~60ms, so the service can
afford to block:

1. SpringBoard receives a video/photo trigger on iOS 18, posts
   `JWRNotifyLaunchCameraVideo`/`JWRNotifyLaunchCameraPhoto`, and returns
   immediately (its main thread is busy for ~2ms instead of ~10s).
2. The launch service, already running via launchd `KeepAlive`, receives the
   notification on its main queue, calls `openApplicationWithBundleID:` for the
   companion app inline on the main thread (dlopen-ing MobileCoreServices on
   demand, since the class is not linked into the binary), and logs the result.
3. 1.2 seconds after the open returns, the service posts
   `JWRNotifyForegroundVideo`/`JWRNotifyForegroundPhoto`, giving the app time
   to launch and register its receiver so the toggle is never lost.
4. The companion app receives the toggle and starts or stops video/photo
   capture.

Measured on the iPhone 11 (iOS 18.1.1): trigger to recording start is ~1.7
seconds with zero SpringBoard freeze, versus ~10 seconds frozen before.

One consequence of this design: Darwin notifications are not delivered to the
companion app while iOS has it suspended, so a toggle posted while the app is
backgrounded waits until the app next wakes. Backgrounding interrupts iOS 18
camera capture anyway and the in-flight segment is finalized safely, but the
late toggle is applied with toggle semantics — a stale stop request can flip
an already-stopped recording back on once the app wakes.

## Hardware trigger implementation

`Tweak.xm` hooks:

```text
SBVolumeControl -increaseVolume
SBVolumeControl -decreaseVolume
```

Trigger rules in the current implementation:

- Two presses within 0.38 seconds invoke the configured double-press action.
- If the other volume button is considered held, the both-buttons action runs.
- The original system volume behavior is still called with `%orig`.
- `JWRRun` ignores all actions when the tweak is disabled.
- `JWRRun` ignores actions while locked unless `triggersWhileLocked` is enabled.

The action enum is:

| Value | Action |
| ---: | --- |
| `0` | None |
| `1` | Video |
| `2` | Audio |
| `3` | Photo |

Long-press and power-action properties exist in `JWRPreferences`, but they are
not complete user-facing features. See **Known limitations and dormant
scaffolding**.

## Wake suppression

During active video, and only when `preventWakeWhileRecording` is enabled, the
tweak suppresses:

```text
SBLiftToWakeManager
  -liftToWakeController:didObserveTransition:deviceOrientation:

SBLockScreenManager
  -_wakeScreenForTapToWake
```

These are private SpringBoard methods and may change on another firmware. The
hooks should always fall through to `%orig` when no video is active.

## Recorder concurrency model

`JWRRecorderManager` is a singleton in each process. It creates the serial
queue:

```text
com.jimwas.recorder.capture
```

Capture state mutations and timers should stay on this queue. AVFoundation
delegate callbacks are dispatched back to the queue before they modify shared
state.

The two most important video state variables are:

- `desiredVideoRecording`: what the user wants.
- `videoRecording`: what the manager currently believes AVFoundation is doing.

This distinction allows the watchdog to rebuild the session while preserving
the user's requested recording state.

Related flags:

- `rollingSegment`: the current stop was requested by the configured segment
  timer.
- `recoveryInProgress`: the current stop/rebuild belongs to watchdog recovery.
- `recoveryAttempts`: controls recovery backoff.

Do not replace this with a single boolean. A single state bit cannot distinguish
a manual stop, a segment boundary, and an unexpected AVFoundation stop.

## Video start sequence

`toggleVideo` dispatches to the serial queue.

When starting:

1. Set `desiredVideoRecording = YES`.
2. Build an `AVCaptureSession` with `AVCaptureSessionPresetInputPriority`.
3. Select the requested camera, falling back from unsupported 0.5x to the wide
   camera.
4. Choose and lock a camera format.
5. Add camera and microphone inputs.
6. Add `AVCaptureMovieFileOutput` and `AVCapturePhotoOutput`.
7. Set `movieFragmentInterval` to two seconds.
8. Register runtime-error and interruption observers.
9. Enable multitasking camera access when the device reports support.
10. Start the session.
11. Create a staged `.mov` URL under `.inprogress`.
12. Attach QuickTime metadata.
13. Start movie recording.
14. Start segment, watchdog, and heartbeat timers as applicable.
15. Post the confirmed video-start haptic unless this is a watchdog restart.

When stopping manually:

1. Set `desiredVideoRecording = NO`.
2. Cancel segment and watchdog timers.
3. Ask `AVCaptureMovieFileOutput` to stop.
4. Wait for the file-output delegate.
5. Finalize the staged movie.
6. Tear down the session.
7. Post the strong video-stop vibration.

The stop vibration is deliberately emitted after delegate finalization rather
than when the trigger is first received.

## Camera format selection

Preference values map to dimensions as follows:

| `videoQuality` | Requested dimensions |
| ---: | --- |
| `-1` | 640 × 480 |
| `0` | 1280 × 720 |
| `1` | 1920 × 1080 |
| `2` | 3840 × 2160 |

The format scorer heavily prioritizes exact resolution, then whether the format
supports the requested FPS, then pixel-count distance, then maximum frame rate.
The final FPS is clamped to the selected format's supported range.

This means a displayed choice is a request, not a guarantee. Always inspect the
log line containing:

```text
camera format requested=... actual=... supportedRange=...
```

The Settings bundle queries physical devices and hides the lens picker when the
selected camera has only one supported lens. The runtime independently falls
back to 1x if an old preference requests an unavailable ultra-wide camera.

## Segmentation and crash recovery

### Normal finalization

Active video is written to:

```text
<videoOutputDirectory>/.inprogress/<name>.mov
```

The default `videoOutputDirectory` is
`/var/mobile/Documents/JimWasRecorder`. Settings accepts writable absolute
paths under `/var/mobile` and creates the selected folder when necessary.

`AVCaptureMovieFileOutput.movieFragmentInterval` is two seconds. Fragmented
QuickTime output improves the chance that an interrupted staged file remains
playable.

When the file-output delegate reports success:

1. Treat a nil error as success.
2. Also treat an error as success when
   `AVErrorRecordingSuccessfullyFinishedKey` is true.
3. Require at least 16 KiB, a video track, and 0.10 seconds of numeric duration.
4. Delete a failed staged file when it is smaller than 16 KiB; retain larger
   invalid files in `.inprogress` for possible manual recovery.
5. Atomically move a validated staged file into the main output directory.
6. Add a UUID suffix if the final filename already exists.
7. Apply `videoStorageMode`: keep the local file, import it and remove the local
   source after success, or keep it and also import it.

### Configurable segment rotation

When `videoSegmentDurationSeconds` is greater than zero, a one-shot dispatch
timer fires after the configured duration:

1. Set `rollingSegment = YES`.
2. Stop the current `AVCaptureMovieFileOutput`.
3. Wait for the delegate and finalize the movie.
4. Create a new staged URL.
5. Reapply metadata.
6. Start the next recording and schedule the next boundary.

The implementation still uses stop/start rotation. A short gap between segments
is possible. Moving to an `AVAssetWriter` sample-buffer pipeline would be the
appropriate path for near-gapless rotation, but it would replace the current
capture pipeline and requires device-level stress testing.

### Startup recovery

At SpringBoard launch, `recoverPendingRecordings` scans `.inprogress` once per
manager lifetime. A staged movie is moved to the main directory with a
`Recovered_` prefix when:

- `AVURLAsset.playable` is true.
- It is at least 16 KiB and contains a video track.
- Its duration is numeric and greater than 0.10 seconds.

Unplayable staged files below 16 KiB are logged and deleted so a failed capture
cannot accumulate container-only MOV files. Larger invalid files remain staged
for possible manual repair instead of risking destruction of captured media.
Recovered files are not automatically copied to Photos.

Fragmentation improves resilience but cannot guarantee recovery from every
power loss, storage failure, or media-server crash.

## Recording watchdog

The watchdog runs every five seconds while video is desired. It does nothing
during a planned segment roll or an active recovery.

Recovery begins when:

- The capture session is no longer running.
- The movie output is no longer recording.
- A runtime error is received.
- An interruption ends without recording becoming active again.
- The delegate reports an unexpected stop.

The recovery path:

1. Posts a failure haptic.
2. Cancels the segment timer.
3. Stops the current movie if possible so its delegate can finalize it.
4. Forces teardown if stop has not completed after four seconds.
5. Rebuilds the session with exponential retry delays.

Retries are scheduled after 2, 4, 8, and 16 seconds. A restart does not reset
the failure count merely because `startRecording` returned. The counter resets
only after the same output remains active and reports at least one second of
recorded media at the five-second health check. After five consecutive failures,
the circuit breaker clears the desired recording state, tears down capture, and
posts a strong failure haptic. Watchdog restarts intentionally do not play the
manual video-start vibration.

## Audio-only recording

Audio-only capture runs in the launch service and uses `AVAudioRecorder`.

Current format:

- MPEG-4 AAC.
- 44.1 kHz.
- Mono.
- High encoder quality.
- `.m4a` output.

The audio session uses `PlayAndRecord`, `MixWithOthers`, and
`DefaultToSpeaker`. Unexpected completion or encoder errors post failure
feedback. Original audio files are not copied to Photos.

When `saveAudioAsVideo` is enabled, successful audio completion also starts an
offline passthrough composition export:

1. The completed `.m4a` remains untouched as the source and fallback.
2. The AAC audio track is inserted into an `AVMutableComposition` without
   transcoding.
3. The bundled one-second 720×1280 H.264 black-video template is inserted and
   time-scaled to the audio duration.
4. The movie is written inside `<videoOutputDirectory>/.inprogress`.
5. Successful output is atomically finalized into `videoOutputDirectory`.
6. Apply `videoStorageMode`: retain locally, import and delete locally after
   success, or retain locally and import.
7. Failed partial movies are removed and trigger failure feedback; the original
   `.m4a` remains playable.

This path never opens an `AVCaptureDevice`, so enabling it does not activate the
camera. `AVAssetExportPresetPassthrough` avoids video or audio re-encoding,
which keeps conversion time, memory use, and battery use low.

## Photo capture

Photos use `AVCapturePhotoOutput` with quality prioritization. The returned data
is decoded to `UIImage`, recompressed as JPEG using the internal
`photoQuality` preference, and written atomically.

A successful write posts the photo haptic. If enabled, the file is also copied
to Photos. The capture session is stopped after the photo when video is not
active.

## Metadata and location

Every video receives QuickTime metadata for:

- Creation date.
- Make.
- Device model.
- JimWas Recorder software version.

When GPS metadata is enabled, the launch service keeps
`location.plist` current with:

- Latitude.
- Longitude.
- Altitude.
- Horizontal accuracy.
- Vertical accuracy.
- Timestamp.

The recorder accepts cached locations no older than 15 minutes and writes an
ISO 6709 location string plus horizontal accuracy.

Location updates use best accuracy, a five-meter distance filter, background
updates, and disabled automatic pausing. This can affect battery life.

## Haptic implementation

SpringBoard owns physical feedback so notifications from the launch service can
still produce device haptics.

Video uses the private exported
`AudioServicesPlaySystemSoundWithVibration` symbol when available:

- Start: two 360 ms pulses separated by 180 ms.
- Stop: one 650 ms pulse.

If that symbol is unavailable, the code falls back to
`UIImpactFeedbackGenerator` with system sound 1520.

Other patterns use AudioServices system sounds:

- Audio start: two 1520 pulses.
- Audio stop: one 1520 pulse.
- Photo/heartbeat: 1519.
- Failure: three 1521 pulses.

Private vibration symbols and numeric system sound identifiers are not stable
public API. Test on every target device family.

## Preferences

Preferences use the domain:

```text
com.jimwas.recorder
```

Settings writes the domain and posts `JWRNotifyReload`. Both runtime processes
reload their singleton. Active health timers are rescheduled immediately.

### Exposed preferences

| Key | Type | Default | Behavior |
| --- | --- | --- | --- |
| `enabled` | Boolean | `true` | Enables hardware-trigger routing. |
| `filenamePrefix` | String | `JWR` | Prefix for generated files. |
| `videoOutputDirectory` | String | `/var/mobile/Documents/JimWasRecorder` | Writable absolute folder under `/var/mobile` used for video staging and finalized movies. |
| `cameraPosition` | Integer | `0` | `0` back, `1` front. |
| `zoom` | Number | `1.0` | `0.5` requests ultra-wide, `1.0` requests wide. |
| `fps` | Integer | `30` | Requested video frame rate. |
| `videoQuality` | Integer | `1` | `-1` 480p, `0` 720p, `1` 1080p, `2` 4K. |
| `videoStorageMode` | Integer | `2` | `0` save folder only, `1` Camera Roll only, `2` both. Photos-only deletes the local finalized movie only after a successful import. |
| `saveAudioAsVideo` | Boolean | `false` | Creates a black-screen MOV copy of each successful audio-only recording. |
| `videoSegmentDurationSeconds` | Integer | `0` | Segment length in seconds; `0` disables rotation. Settings accepts 10–86400 seconds. |
| `embedLocationMetadata` | Boolean | `false` | Enables location caching and QuickTime GPS metadata. |
| `savePhotoToPhotos` | Boolean | `true` | Copies photos to Photos. |
| `doubleVolumeUpAction` | Integer | `1` | Default video toggle. |
| `doubleVolumeDownAction` | Integer | `2` | Default audio toggle. |
| `bothVolumesAction` | Integer | `3` | Default photo action. |
| `preventWakeWhileRecording` | Boolean | `true` | Suppresses raise/tap wake during active video. |
| `triggersWhileLocked` | Boolean | `false` | Allows volume triggers while the UI is locked. |
| `triggersWhileAudioPlaying` | Boolean | `false` | Not enforced; the Settings row was removed until it is implemented. |
| `haptics` | Boolean | `true` | Enables recorder feedback notifications and playback. |
| `recordingHeartbeatInterval` | Integer | `0` | `0`, `30`, `60`, `120`, or `300` seconds. |

When `videoStorageMode` has never been stored, the loader migrates the former
`saveVideoToPhotos` Boolean: `true` becomes `2` (Both) and `false` becomes `0`
(Save Folder Only). Camera Roll-only capture must still stage and finalize a
temporary local movie because Photos imports from a file URL. If import fails,
the local file is retained as the only safe copy.

### Internal or dormant preferences

| Key | Default | Current status |
| --- | ---: | --- |
| `photoQuality` | `0.92` | Used by JPEG encoding but not exposed in Settings. |
| `longVolumeUpAction` | `0` | Read and referenced by trigger code but not exposed; current button-release timing prevents reliable long-press activation. |
| `longVolumeDownAction` | `0` | Same limitation as Volume Up. |
| `powerAction` | `0` | Read but no power-button hook is implemented. |

## Package layout

The Theos rootless package installs these primary artifacts:

```text
/var/jb/Library/MobileSubstrate/DynamicLibraries/JimWasRecorder.dylib
/var/jb/Library/MobileSubstrate/DynamicLibraries/JimWasRecorder.plist
/var/jb/Applications/JWRRecorderApp.app/
/var/jb/Library/PreferenceBundles/JimWasRecorderPrefs.bundle/
/var/jb/Library/PreferenceLoader/Preferences/JimWasRecorder.plist
/var/jb/Library/ControlCenter/Bundles/JWRVideoModule.bundle/
/var/jb/Library/ControlCenter/Bundles/JWRAudioModule.bundle/
/var/jb/Library/LaunchDaemons/com.jimwas.recorder.service.plist
```

The injection filter targets only `com.apple.springboard`.

The app entitlements include non-containerized access, nonstandard AVFoundation
capture, multitasking camera access, and `get-task-allow`. These are
jailbreak-specific and inappropriate for an App Store build.

## Logging and diagnostics

All processes append to:

```text
/var/mobile/Documents/JimWasRecorder/debug.log
```

Each line includes timestamp, process name, PID, and message. `JWRLog` also
writes to `NSLog`.

Useful checks:

```sh
dpkg-query -W com.jimwas.recorder

launchctl print system/com.jimwas.recorder.service

tail -n 200 /var/mobile/Documents/JimWasRecorder/debug.log

ls -lah /var/mobile/Documents/JimWasRecorder

ls -lah '<configured-video-folder>'

ls -lah '<configured-video-folder>/.inprogress'
```

Expected startup messages include:

```text
[JWRRecorderApp:<pid>] service starting
[SpringBoard:<pid>] SpringBoard trigger component loaded
```

The primary persistent log is:

```text
/var/mobile/Library/Logs/JimWasRecorder/debug.log
```

If that location cannot be created, logging falls back to the standard output
folder and then `/tmp/JimWasRecorder/debug.log`.

Expected video-start messages include:

```text
SpringBoard received video toggle
preparing capture session withAudio=1
camera format requested=... actual=...
capture startRunning returned running=1 interrupted=0
video+audio recording started url=.../.inprogress/...
video watchdog scheduled every 5 seconds
```

## Troubleshooting

### Settings page is missing

- Confirm PreferenceLoader is installed.
- Confirm the preference bundle and loader entry exist under `/var/jb/Library`.
- Kill Settings and respring.
- Check `debug.log` for `Settings requested specifiers`.

### Settings page is blank

- Validate `prefs/Resources/Root.plist` with `plutil -lint`.
- Confirm the plist is present inside the installed preference bundle.
- Check the logged definition and specifier counts.
- Keep picker keys in `pickerKeys`; the custom action-sheet path exists to avoid
  firmware-specific list-controller crashes.

### Control Center modules are missing

- Confirm both bundles exist under
  `/var/jb/Library/ControlCenter/Bundles`.
- Respring after installation.
- Open Control Center settings and add **Recorder Video** and
  **Recorder Audio**.

### Trigger logs but no video starts

- Run `dpkg-query -W oldabi` first. Install or repair **Legacy arm64e Support**
  2.0.1 or newer if the query fails. Do not infer that injection is healthy
  merely because trigger lines appear in the log; missing legacy ABI support
  can produce partial, misleading operation.
- Open the companion app and verify Camera and Microphone show Granted.
- Inspect the camera-input, format, and `startRunning` log lines.
- Confirm capture is executing in SpringBoard (iOS 16) or the companion app
  (iOS 18), not the launch service.
- On iOS 18, confirm the relay chain in the logs: `camera host launch delegated
  to service` from SpringBoard, then `service opened camera host opened=1` from
  the launch service. `opened=0` means the app was already running, which is
  expected when it is already foregrounded.
- Remove unsupported stored camera preferences if fallback also fails.

### Audio toggle does nothing

- Confirm the launch service is running.
- Look for `received audio toggle`.
- Check microphone authorization and audio-session errors.

### Video stops unexpectedly

- Find the first `capture runtime error`, `capture interrupted`, or watchdog
  line before the stop.
- Confirm the recovery path schedules a retry.
- Inspect `.inprogress` and final output directories.
- Do not delete staged files until their playability has been evaluated.

### SpringBoard is black or repeatedly crashes

SSH into the device and respring:

```sh
/var/jb/usr/bin/sbreload
```

If the crash loop is caused by this package, uninstall it from SSH:

```sh
dpkg -r com.jimwas.recorder
/var/jb/usr/bin/sbreload
```

Preserve `debug.log` and `.inprogress` before removing user recordings.

## Known limitations and dormant scaffolding

These are current source facts, not planned marketing features:

1. Long-press volume actions are not exposed in Settings and are not reliable
   with the current release-reset timing.
2. `powerAction` has no SpringBoard power-button hook.
3. `triggersWhileAudioPlaying` is stored but still not enforced; its Settings
   row was removed so users are not offered an option that does nothing.
4. `JWRNotifyState` carries a video/audio active bitmask; Control Center
   modules subscribe and mirror the actual recorder state. State is
   event-driven, so a toggle can briefly lag a transition.
5. Movie segment rotation uses stop/start and may have a brief gap.
6. Crash recovery moves only staged movies that AVFoundation already considers
   playable. It does not repair corrupt media.
7. Recovered movies are not automatically copied to Photos.
8. Camera format choices are requested values and may be clamped or substituted
   by hardware capability.
9. Photo quality exists as an internal preference but has no Settings control.
10. The companion app's bundle version is maintained separately from the Debian
    package version.
11. Private SpringBoard hooks, private ControlCenterUIKit behavior, haptic
    symbols, and numeric system sounds may change across firmware.
12. Darwin notifications do not wake the suspended companion app on iOS 18, so
    a toggle posted while it is backgrounded is delivered only when the app
    next wakes, and is then applied with toggle semantics (see the launch-relay
    note above).

## Safe extension patterns

### Adding a preference

1. Add the property to `JWRPreferences.h`.
2. Load it with a safe default in `JWRPreferences.m`.
3. Add its specifier to `prefs/Resources/Root.plist`.
4. Add its key to `pickerKeys` if it uses the custom action-sheet picker.
5. Decide which processes need to react immediately on `JWRNotifyReload`.
6. Test default migration from an older installed preferences domain.

### Adding a trigger action

1. Extend `JWRAction` without renumbering existing values.
2. Add the display title/value to every trigger specifier.
3. Route the action in `JWRRun`.
4. Define a Darwin notification if another process owns the operation.
5. Add receiver lifecycle and logging.
6. Test double presses, both-buttons timing, lock state, and normal volume
   behavior.

### Changing video lifecycle

1. Preserve the distinction between desired and actual recording state.
2. Keep file state changes on the serial capture queue.
3. Let the file-output delegate decide whether a movie completed successfully.
4. Finalize or preserve the current staged file before starting another.
5. Keep manual stop, planned segment roll, and watchdog recovery distinguishable.
6. Test start, stop, lock, 120-second roll, media-service interruption,
   SpringBoard respring, low storage, and Photos copy.

### Replacing `AVCaptureMovieFileOutput`

An `AVAssetWriter` implementation should use video and audio data outputs,
timestamp-aligned sample buffers, and a writer state machine that can rotate
destinations without tearing down the capture session. It must also reproduce:

- Format/FPS selection.
- Metadata.
- Staged atomic finalization.
- Photos copying.
- Watchdog recovery.
- Haptics only after confirmed state changes.
- Crash recovery or short-duration fragmented output.

Keep the existing pipeline available behind a development preference until the
writer path has survived long locked-screen tests.

## Release checklist

1. Update `Version` in `control`.
2. Update the QuickTime software metadata version in
   `JWRRecorderManager.m`.
3. Decide whether the companion and module bundle versions should be updated.
4. Add the release to `CHANGELOG.md`.
5. Run:

   ```sh
   plutil -lint prefs/Resources/Root.plist
   make clean package FINALPACKAGE=1
   ```

6. Inspect the package:

   ```sh
   dpkg-deb -I packages/com.jimwas.recorder_<version>_iphoneos-arm64.deb
   dpkg-deb -c packages/com.jimwas.recorder_<version>_iphoneos-arm64.deb
   ```

7. Confirm `dpkg-query -W oldabi` reports Legacy arm64e Support 2.0.1 or newer
   on every arm64e test device.
8. Install on a test device with SSH available.
9. Verify Settings, both Control Center modules, companion permissions, and
   service startup.
10. Record and finalize a short rear-camera clip.
11. Record and finalize a short front-camera clip.
12. Test short, 120-second, disabled, and changed-while-recording segment
    settings.
13. Test screen lock, wake suppression, heartbeat, and stop feedback.
14. Review `debug.log` for runtime errors.
15. Preserve the previous known-good `.deb` for rollback.
