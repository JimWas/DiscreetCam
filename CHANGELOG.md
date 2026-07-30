# Changelog

Notable changes to JimWas Recorder are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) where practical.

Because versions 1.0.x and 1.1.x were rapid device-debugging builds, their
individual changes were not preserved in source control. They are grouped below
rather than assigning unsupported details to a specific build.

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
