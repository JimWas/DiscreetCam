# Changelog

Notable changes to JimWas Recorder are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) where practical.

Because versions 1.0.x and 1.1.x were rapid device-debugging builds, their
individual changes were not preserved in source control. They are grouped below
rather than assigning unsupported details to a specific build.

## [Unreleased]

### Fixed

- Eliminate the ~10 second SpringBoard freeze on every iOS 18 video/photo
  trigger. `openApplicationWithBundleID:` must run on a process's main thread
  or it silently refuses to launch the app, and iOS 18.1.1 has no async
  variant, so SpringBoard now delegates the open to the companion launch
  service, which performs it on its own main thread in ~60ms. Trigger-to-
  recording latency dropped from ~10s with a frozen UI to ~1.7s.
- Route the Control Center video module through the trigger notification on
  iOS 18 so tapping it foregrounds the companion app and toggles video instead
  of posting a notification that no process receives; the trigger receiver now
  registers on every firmware, which also makes `--trigger-video` work on the
  iOS 16 path.
- Declare **Legacy arm64e Support** (`oldabi` 2.0.1 or newer) as a package
  dependency and document it as the first troubleshooting check for partial
  injection, failed video capture, or missing haptic feedback on Dopamine.
- Synchronize the Control Center video and audio toggles with the actual
  recorder state: the recorder publishes a 0/1 active flag on separate
  single-writer video and audio state notifications that both modules
  subscribe to, so a toggle no longer stays lit after a denied trigger or
  fails to show a recording started from the hardware buttons. State publishes
  on every recording start and stop, including watchdog recovery and segment
  rolls, and separate writers mean concurrent video/audio transitions cannot
  overwrite each other.
- Route the Control Center modules through SpringBoard's shared trigger
  receivers on every firmware (the audio module gains `JWRNotifyTriggerAudio`),
  so the **Enabled** and locked-screen gates apply to Control Center toggles
  exactly like volume-button triggers; the iOS 16 video module previously
  posted the direct toggle and ignored both gates.
- Remove the inactive **Allow While Other Audio Plays** Settings row, which
  stored a preference that no code enforced.
- Sanitize the filename prefix (strip slashes, fall back when blank) so a
  path-like prefix cannot break output-file naming.
- Cap `debug.log` at 5 MB and remove SpringBoard startup method-list
  introspection, preventing unbounded log growth from the always-on service.

### Known Issues

- Darwin notifications are not delivered to the companion app while iOS has
  suspended it, so a video toggle posted while the app is backgrounded waits
  until the app next wakes. Because backgrounding interrupts iOS 18 camera
  capture anyway, footage is still finalized safely, but a late-delivered
  toggle is applied with toggle semantics and can flip an already-stopped
  recording back on.

## [2.0.0] - 2026-09-02

### Added

- Add an iOS 18 camera compatibility path that foregrounds the companion app
  and owns video/photo capture there, avoiding SpringBoard's new background
  camera denial while retaining the original iOS 16 SpringBoard path.
- Add explicit foreground video/photo diagnostic notifications for device tests.
- Bootstrap the mobile launch service during package installation on newer
  Dopamine launchd domains.

## [2.0.1] - 2026-09-02

### Fixed

- Detect iOS 18 hardware volume presses through SpringBoard's system-volume
  notification because the legacy `SBVolumeControl` method hook no longer
  receives the physical button events on iOS 18.1.1.
- Add an end-to-end diagnostic video trigger for validating foreground app
  launch and camera routing independently of hardware input.

## [1.9.9] - 2026-08-20

### Fixed

- Restore video and photo capture handling to SpringBoard, matching the last
  configuration proven to record successfully on iOS 16.3.
- Keep audio handling in the companion launch service and preserve the newer
  diagnostics and reliable vibration fallback.

## [1.9.8] - 2026-08-20

### Fixed

- Add standard system-vibration and heavy-impact fallbacks when private patterned
  vibration calls execute without producing physical feedback.

## [1.9.7] - 2026-08-20

### Added

- Add an in-app diagnostic log viewer with refresh and copy controls.
- Log exact authorization values, application lifecycle changes, background time,
  and recorder-service readiness from the companion app.

## [1.9.6] - 2026-08-20

### Added

- Add a companion-app control to reset Camera, Microphone, Photos, and Location
  permissions for JimWas Recorder, with confirmation and explicit error results.

## [1.9.5] - 2026-08-20

### Fixed

- Correct the private AVFoundation nonstandard-client entitlement name and add
  the platform capture/background-camera permissions required by the recorder
  service on iOS 16.

## [1.9.4] - 2026-08-20

### Fixed

- Route video and photo capture through the entitled companion service instead
  of SpringBoard, avoiding background-camera interruption failures on iOS 16.
- Keep SpringBoard responsible only for hardware triggers and haptic feedback,
  preventing duplicate capture handlers across processes.

## [1.9.3] - 2026-08-13

### Added

- New **Save Videos To** choice with **Save Folder Only**, **Camera Roll Only**,
  and **Both** destinations.
- Safe Camera Roll-only cleanup for camera recordings and optional black-screen
  video copies created from audio recordings.

### Changed

- Camera Roll-only recordings are temporarily staged and validated locally,
  imported into Photos, and removed from the save folder only after Photos
  reports success.
- A failed Photos import retains the local movie as a safety fallback and emits
  failure feedback instead of deleting the only copy.
- Existing `saveVideoToPhotos` preferences migrate automatically: enabled maps
  to **Both**, while disabled maps to **Save Folder Only**.
- The custom video-folder row is hidden while **Camera Roll Only** is selected.
- QuickTime software metadata now identifies version 1.9.3.

## [1.9.2] - 2026-08-03

### Fixed

- Reject header-only, empty, or otherwise unplayable staged movies instead of
  publishing them as completed recordings.
- Delete clear header-only failures while retaining nontrivial invalid staged
  files in `.inprogress` for possible manual recovery.
- Preserve the consecutive recovery-failure count until AVFoundation has
  recorded healthy media for five seconds.
- Stop automatic recovery after five consecutive failures, preventing an
  unlimited loop that could create hundreds of empty MOV files.
- Ignore stale delayed-retry blocks after recording is stopped or superseded.
- Write diagnostics to `/var/mobile/Library/Logs/JimWasRecorder/debug.log`,
  with Documents and `/tmp` fallbacks when the primary location is unavailable.

### Changed

- Recovery now uses exponential delays of 2, 4, 8, and 16 seconds before the
  circuit breaker stops recording and sends a strong failure haptic.
- QuickTime software metadata now identifies version 1.9.2.

## [1.9.1] - 2026-07-31

### Added

- New teal camera-lens and audio-waveform product icon.
- Home Screen icon resources at iPhone 2x and 3x sizes.
- Settings preference icon.
- 1024×1024 master artwork for package repositories and marketing.

### Changed

- QuickTime software metadata now identifies version 1.9.1.

## [1.9.0] - 2026-07-30

### Added

- Optional **Create Video Copy of Audio** setting.
- Post-recording passthrough composition export from audio-only M4A to a
  genuine 720×1280 black-screen QuickTime movie.
- Bundled one-frame H.264 template that is time-scaled to the audio duration
  without re-encoding.
- Crash-safe staging and atomic finalization for generated audio-video copies.
- Photos-library copying for generated movies when **Copy Videos to Photos** is
  enabled.

### Changed

- Audio-video copies follow the configured video save folder while original
  M4A recordings remain in the default Documents folder.
- The original M4A is preserved when conversion fails.
- Generated movies reuse the original AAC stream and black H.264 template,
  minimizing conversion time, memory use, and battery use.
- QuickTime software metadata now identifies version 1.9.0.

## [1.8.1] - 2026-07-29

### Added

- Custom video save-folder editor in Settings.
- Validation and automatic creation of writable absolute paths under
  `/var/mobile`.
- One-tap restoration of the default video folder.

### Changed

- Video staging, finalization, segment rotation, and recovery use the selected
  video folder.
- Audio-only recordings, photos, GPS cache, and diagnostics remain in the
  standard JimWas Recorder Documents folder.
- Finalization remembers the directory in which a segment was staged, making a
  folder change safe during an active recording.
- Startup recovery checks both the selected folder and the default folder.

## [1.8.0] - 2026-07-29

### Added

- Custom video segment duration editor in Settings.
- Human-readable segment-length summaries in seconds and minutes.
- Validation for segment durations from 10 through 86400 seconds, with `0`
  disabling segmentation.

### Changed

- Existing installations with the former two-minute switch enabled migrate to
  a 120-second custom duration.
- Segment timers use the configured duration and are rescheduled when
  preferences change during an active recording.
- Embedded QuickTime software metadata now identifies version 1.8.0.

## [1.7.2] - 2026-07-29

### Fixed

- Replaced the basic full-device vibration call with an iPhone SE 2-compatible
  explicit vibration pattern.
- Added a heavy `UIImpactFeedbackGenerator` and system-sound fallback when the
  private vibration function is unavailable.

### Changed

- Video start uses two 360 ms vibration pulses separated by 180 ms.
- Video stop uses one 650 ms vibration pulse.

## [1.7.1] - 2026-07-29

### Added

- Dedicated video-start and video-stop haptic notifications.
- Strong video feedback shared by hardware-trigger and Control Center paths.

### Changed

- Video start confirmation is emitted only after the recording command is
  accepted by the prepared session.
- Video stop confirmation is emitted after the output delegate finalizes the
  movie.
- Watchdog restarts do not imitate manual start feedback.

## [1.7.0] - 2026-07-29

### Added

- Five-second video health watchdog.
- Automatic capture-session rebuild after runtime errors, interruptions, or
  unexpected output stops.
- Increasing recovery retry delay capped at ten seconds.
- Distinct failure haptic.
- Configurable healthy-recording heartbeat at 30, 60, 120, or 300 seconds.
- Hidden `.inprogress` staging directory for active movies.
- Automatic recovery of playable staged movies at SpringBoard startup.
- `Recovered_` filename prefix for recovered movies.
- Two-second QuickTime movie fragments to improve interrupted-file playability.
- Device-aware lens detection in Settings.

### Changed

- Finalized staged movies are atomically moved into the main output directory.
- Two-minute rotation finalizes the current movie before starting the next.
- AVFoundation errors with `AVErrorRecordingSuccessfullyFinishedKey = true` are
  treated as successful output.
- Unsupported 0.5x requests fall back to the 1x wide camera.
- The lens picker is hidden when the selected camera has only one lens.
- Active heartbeat/watchdog timers refresh when preferences change.

## [1.6.1] - 2026-07-29

### Added

- Confirmed-state haptic notifications for recording start, recording stop, and
  successful photo capture.
- Double start haptic, single stop haptic, and light photo haptic.

## [1.6.0] - 2026-07-29

### Added

- Video quality choices for 480p, 720p, 1080p, and 4K.
- FPS choices for 24, 25, 30, 60, 120, and 240.
- Camera-format scoring across resolution and supported frame-rate ranges.
- Logging of requested versus actual dimensions and FPS.

### Changed

- Requested FPS is clamped to the selected hardware format's supported range.

## [1.5.1] - 2026-07-29

### Changed

- Converted camera, lens, FPS, and quality rows to stable action-sheet pickers.
- Reduced dependence on firmware-sensitive Preferences list controllers.

## [1.5.0] - 2026-07-29

### Added

- Rear/front camera selection.
- Optional suppression of raise-to-wake and tap-to-wake during active video.
- Stable action-sheet pickers for trigger actions.

### Fixed

- Restored editable trigger choices after the previous Settings implementation
  became blank.

## [1.4.0] - 2026-07-29

### Added

- Background location provider in the launch service.
- Cached latitude, longitude, altitude, accuracy, and timestamp.
- Optional QuickTime ISO 6709 location metadata.
- QuickTime creation date, make, model, and software metadata.
- Companion-app Always Location permission request.

## [1.3.1] - 2026-07-29

### Fixed

- Replaced crash-prone trigger selection rows with custom action-sheet pickers.

## [1.3.0] - 2026-07-29

### Added

- Optional two-minute video segmentation.
- Automatic continuation into a new movie after a planned segment boundary.

## [1.2.0] - 2026-07-29

### Changed

- Moved video and photo capture ownership into SpringBoard.
- Kept audio-only capture in the separate launch service.

### Fixed

- Resolved background camera interruption encountered when video capture ran
  only in the service process.
- Restored working video with microphone audio during locked/background use.

## [1.0.0–1.1.4] - 2026-07-29

### Added

- Initial rootless Debian package and SpringBoard injection.
- Companion permission application.
- Settings preference bundle.
- Video and audio Control Center modules.
- Darwin-notification command routing.
- Hardware volume-button action routing.
- Video, audio-only, and photo output to the mobile Documents directory.
- Optional Photos-library copies for video and photos.
- Shared cross-process debug logging.

### Fixed

- Early package-layout, Settings loading, Control Center discovery, permission,
  launch-service, SpringBoard stability, and video-capture integration issues
  across iterative device-debugging builds.
