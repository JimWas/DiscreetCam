# JimWas Recorder

JimWas Recorder is a rootless jailbreak tweak for background video, audio, and
photo capture on iOS 16. It was developed and tested primarily on iOS 16.3 with
Dopamine, including iPhone SE 2 and iPhone SE 3.

The package adds:

- Background video recording with microphone audio.
- Background audio-only recording.
- Background photo capture.
- Configurable volume-button triggers.
- Video and audio modules for Control Center.
- Front/rear camera selection and device-aware lens choices.
- Video choices from 480p through 4K and 24 through 240 FPS, subject to the
  selected camera's supported formats.
- Custom-length movie segments from 10 seconds through 24 hours, or one
  continuous file.
- Configurable video output folder under `/var/mobile`.
- Recording health monitoring, restart recovery, and crash-recoverable staged
  movie files.
- Optional QuickTime GPS metadata.
- Start, stop, failure, photo, and periodic recording haptics.
- Optional copying of videos and photos to the Photos library.

> [!IMPORTANT]
> This is jailbreak software, not an App Store application. It depends on
> private iOS behavior and SpringBoard hooks that may change between iOS
> releases.

## Requirements

- A compatible iPhone running iOS 16.
- Dopamine or another compatible rootless jailbreak environment.
- ElleKit/Substrate-compatible tweak injection.
- PreferenceLoader.
- Theos with an iOS SDK capable of building the configured target.
- A macOS development machine for building.

The current `Makefile` builds both `arm64` and `arm64e`, targets iOS 15.0 or
later, uses the iOS 16.5 SDK, and packages with the Theos rootless scheme.

## Repository map

| Path | Purpose |
| --- | --- |
| `Tweak.xm` | SpringBoard hooks, hardware triggers, wake suppression, Darwin notification receivers, and haptics. |
| `JWRRecorderManager.m` | Video, photo, audio, segmentation, metadata, watchdog, and file recovery logic. |
| `JWRPreferences.m` | Shared preference-domain loader and defaults. |
| `JWRConstants.h` | Action values and Darwin notification names. |
| `JWRLogger.m` | Unified file and system logging. |
| `JWRLocationProvider.m` | Background location cache used for video metadata. |
| `app/` | Companion permission UI and the separate audio/location service mode. |
| `prefs/` | Settings preference bundle and device-aware option pickers. |
| `modules/` | Control Center video and audio toggle bundles. |
| `layout/` | Files copied directly into the rootless package. |
| `control` | Debian package metadata and package version. |
| `DOCUMENTATION.md` | Detailed architecture, state machines, preferences, debugging, and maintenance notes. |
| `CHANGELOG.md` | Release history through the current package version. |

## Build

The `Makefile` currently defaults `THEOS` to `/Users/jimwashkau/theos`. Override
it in the environment if Theos is installed elsewhere.

```sh
make clean package FINALPACKAGE=1
```

The rootless Debian package is written to `packages/`:

```text
packages/com.jimwas.recorder_<version>_iphoneos-arm64.deb
```

## Install

Copy the package to the device and install it as root:

```sh
scp -P 22 packages/com.jimwas.recorder_<version>_iphoneos-arm64.deb \
  mobile@<iphone-address>:/tmp/com.jimwas.recorder.deb

ssh -p 22 root@<iphone-address> \
  'dpkg -i /tmp/com.jimwas.recorder.deb; /var/jb/usr/bin/sbreload'
```

Do not put passwords in scripts or repository files. Use SSH keys for routine
development.

If the service has not loaded after installation, reboot userspace or bootstrap
the packaged launch daemon:

```sh
launchctl bootstrap system \
  /var/jb/Library/LaunchDaemons/com.jimwas.recorder.service.plist
```

## First run

1. Open **JimWas Recorder** from the Home Screen.
2. Tap **Grant Recording Permissions**.
3. Grant Camera and Microphone access.
4. Grant Photos access if copies should be added to Camera Roll.
5. Grant Always Location access only if GPS metadata is needed.
6. Open **Settings → JimWas Recorder** and configure capture behavior.
7. Add **Recorder Video** and **Recorder Audio** in Control Center if desired.

Default hardware actions are:

- Double Volume Up: toggle video with microphone audio.
- Double Volume Down: toggle audio-only recording.
- Both volume buttons: take a photo.

Locked-screen triggers are disabled by default. Enable **Allow Triggers While
Locked** for screen-off capture.

## Output

By default, original files and diagnostics live under:

```text
/var/mobile/Documents/JimWasRecorder
```

| File | Meaning |
| --- | --- |
| `<prefix>_<timestamp>.mov` | Finalized video with microphone audio. |
| `<prefix>_<timestamp>.m4a` | Audio-only AAC recording. |
| `<prefix>_<timestamp>.jpg` | Captured photo. |
| `Recovered_<name>.mov` | Playable staged movie recovered after an interruption or SpringBoard restart. |
| `.inprogress/*.mov` | Active fragmented movies awaiting finalization or recovery. |
| `location.plist` | Latest cached location used for optional video metadata. |
| `debug.log` | Cross-process diagnostic log. |

The video destination can be changed from **Settings → JimWas Recorder → Video
Save Folder** to any writable absolute folder under `/var/mobile`. Finalized
movies and their crash-safe `.inprogress` staging directory move to the selected
folder. Audio-only recordings, photos, GPS cache, and `debug.log` remain in the
default directory.

Videos and photos may also be copied to Photos when their corresponding
preferences are enabled. Audio-only files remain in Documents.

## Haptic meanings

- Video start: two strong vibration pulses.
- Video stop: one strong vibration after the movie delegate finishes and the
  file is finalized.
- Audio start: two standard haptic pulses.
- Audio stop: one standard haptic pulse.
- Photo success: one light haptic.
- Recording failure or unexpected stop: three warning haptics.
- Recording heartbeat: one light haptic at the configured interval, but only
  while the recorder is healthy.

## Privacy and responsible use

JimWas Recorder intentionally keeps Apple's camera and microphone privacy
indicators enabled. It does not capture telephone or FaceTime call audio.

Use the software only where recording is lawful and appropriate. Obtain consent
when required and comply with all applicable recording and privacy laws.

## Developer documentation

Read [DOCUMENTATION.md](DOCUMENTATION.md) before changing capture ownership,
SpringBoard hooks, the recovery state machine, package layout, or preference
types. Release history is maintained in [CHANGELOG.md](CHANGELOG.md).
