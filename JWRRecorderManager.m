#import "JWRRecorderManager.h"
#import "JWRPreferences.h"
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <AudioToolbox/AudioToolbox.h>
#import <UIKit/UIKit.h>
#import <notify.h>
#import "JWRLogger.h"
#import <limits.h>
#import <math.h>

static const unsigned long long JWRMinimumPlayableMovieBytes = 16 * 1024;
static const NSTimeInterval JWRMinimumPlayableMovieDuration = 0.10;
static const NSInteger JWRMaximumConsecutiveRecoveryFailures = 5;
static const NSTimeInterval JWRHealthyRecordingConfirmationDelay = 5.0;

@interface JWRRecorderManager () <AVCaptureFileOutputRecordingDelegate, AVCapturePhotoCaptureDelegate, AVAudioRecorderDelegate>
@property(nonatomic) dispatch_queue_t queue;
@property(nonatomic) AVCaptureSession *session;
@property(nonatomic) AVCaptureMovieFileOutput *movieOutput;
@property(nonatomic) AVCapturePhotoOutput *photoOutput;
@property(nonatomic) AVAudioRecorder *audioRecorder;
@property(nonatomic) NSURL *videoURL;
@property(nonatomic) id sessionErrorObserver;
@property(nonatomic) id sessionInterruptedObserver;
@property(nonatomic) id sessionInterruptionEndedObserver;
@property(nonatomic) BOOL rollingSegment;
@property(nonatomic) BOOL recoveryInProgress;
@property(nonatomic) BOOL desiredVideoRecording;
@property(nonatomic) BOOL desiredAudioRecording;
@property(nonatomic) BOOL recoveryScanned;
@property(nonatomic) BOOL videoChatAudioSessionActive;
@property(nonatomic) NSInteger recoveryAttempts;
@property(nonatomic) NSUInteger recordingGeneration;
@property(nonatomic) dispatch_source_t segmentTimer;
@property(nonatomic) dispatch_source_t heartbeatTimer;
@property(nonatomic) dispatch_source_t watchdogTimer;
@property(nonatomic, readwrite) BOOL videoRecording;
@property(nonatomic, readwrite) BOOL audioRecording;
- (void)handleFinalizedVideoAtURL:(NSURL *)finishedURL context:(NSString *)context;
@end

@implementation JWRRecorderManager
+ (instancetype)shared {
    static JWRRecorderManager *m; static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [self new]; m.queue = dispatch_queue_create("com.jimwas.recorder.capture", DISPATCH_QUEUE_SERIAL); });
    return m;
}
- (NSString *)outputDirectory {
    return @"/var/mobile/Documents/JimWasRecorder";
}
- (NSString *)videoOutputDirectory {
    return [JWRPreferences shared].videoOutputDirectory;
}
- (NSString *)inProgressDirectory {
    return [[self videoOutputDirectory] stringByAppendingPathComponent:@".inprogress"];
}
- (NSURL *)outputURLWithExtension:(NSString *)ext directory:(NSString *)dir {
    NSError *directoryError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&directoryError];
    if (directoryError) JWRLog(@"output directory creation failed path=%@ error=%@", dir, directoryError);
    NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"yyyy-MM-dd_HH-mm-ss-SSS";
    NSString *name = [NSString stringWithFormat:@"%@_%@.%@", [JWRPreferences shared].filenamePrefix, [f stringFromDate:NSDate.date], ext];
    return [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:name]];
}
- (NSURL *)outputURLWithExtension:(NSString *)ext {
    return [self outputURLWithExtension:ext directory:[self outputDirectory]];
}
- (void)prepareVideoURLs {
    NSURL *finalURL = [self outputURLWithExtension:@"mov" directory:[self videoOutputDirectory]];
    NSString *stagingDirectory = [self inProgressDirectory];
    NSError *stagingError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:stagingDirectory withIntermediateDirectories:YES attributes:nil error:&stagingError];
    if (stagingError) JWRLog(@"video staging directory creation failed path=%@ error=%@", stagingDirectory, stagingError);
    self.videoURL = [NSURL fileURLWithPath:[stagingDirectory stringByAppendingPathComponent:finalURL.lastPathComponent]];
}
- (NSURL *)finalURLForStagedURL:(NSURL *)stagedURL recovered:(BOOL)recovered {
    NSString *name = stagedURL.lastPathComponent;
    if (recovered) name = [@"Recovered_" stringByAppendingString:name];
    NSString *recordingDirectory = stagedURL.URLByDeletingLastPathComponent.URLByDeletingLastPathComponent.path;
    return [NSURL fileURLWithPath:[recordingDirectory stringByAppendingPathComponent:name]];
}
- (BOOL)validateMovieAtURL:(NSURL *)url reason:(NSString **)reason {
    if (!url || ![[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
        if (reason) *reason = @"file does not exist";
        return NO;
    }
    NSError *attributesError = nil;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:&attributesError];
    unsigned long long bytes = [attributes[NSFileSize] unsignedLongLongValue];
    if (attributesError || bytes < JWRMinimumPlayableMovieBytes) {
        if (reason) *reason = [NSString stringWithFormat:@"file is too small (%llu bytes; error=%@)", bytes, attributesError];
        return NO;
    }

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    NSTimeInterval duration = CMTIME_IS_NUMERIC(asset.duration) ? CMTimeGetSeconds(asset.duration) : 0;
    BOOL hasVideo = [asset tracksWithMediaType:AVMediaTypeVideo].count > 0;
    if (!hasVideo || !isfinite(duration) || duration < JWRMinimumPlayableMovieDuration) {
        if (reason) *reason = [NSString stringWithFormat:@"missing video frames (hasVideo=%d duration=%.3f)", hasVideo, duration];
        return NO;
    }
    return YES;
}
- (BOOL)finalizeStagedVideoAtURL:(NSURL *)stagedURL recovered:(BOOL)recovered finalURL:(NSURL **)finalURL {
    if (!stagedURL || ![[NSFileManager defaultManager] fileExistsAtPath:stagedURL.path]) return NO;
    NSString *validationReason = nil;
    if (![self validateMovieAtURL:stagedURL reason:&validationReason]) {
        unsigned long long bytes = [[[[NSFileManager defaultManager] attributesOfItemAtPath:stagedURL.path error:nil]
                                     objectForKey:NSFileSize] unsignedLongLongValue];
        if (bytes < JWRMinimumPlayableMovieBytes) {
            NSError *removeError = nil;
            [[NSFileManager defaultManager] removeItemAtURL:stagedURL error:&removeError];
            JWRLog(@"discarded header-only staged movie path=%@ bytes=%llu reason=%@ removeError=%@",
                   stagedURL.path, bytes, validationReason, removeError);
        } else {
            JWRLog(@"retained nontrivial invalid staged movie for manual recovery path=%@ bytes=%llu reason=%@",
                   stagedURL.path, bytes, validationReason);
        }
        return NO;
    }
    NSURL *destination = [self finalURLForStagedURL:stagedURL recovered:recovered];
    if ([[NSFileManager defaultManager] fileExistsAtPath:destination.path]) {
        NSString *stem = destination.URLByDeletingPathExtension.lastPathComponent;
        destination = [destination.URLByDeletingLastPathComponent URLByAppendingPathComponent:
                       [NSString stringWithFormat:@"%@_%@.mov", stem, NSUUID.UUID.UUIDString]];
    }
    NSError *moveError = nil;
    BOOL moved = [[NSFileManager defaultManager] moveItemAtURL:stagedURL toURL:destination error:&moveError];
    JWRLog(@"video finalize staged=%@ final=%@ moved=%d error=%@", stagedURL.path, destination.path, moved, moveError);
    if (moved && finalURL) *finalURL = destination;
    return moved;
}
- (void)recoverStagedVideosIfNeeded {
    if (self.recoveryScanned) return;
    self.recoveryScanned = YES;
    NSString *defaultStagingDirectory = [[self outputDirectory] stringByAppendingPathComponent:@".inprogress"];
    NSMutableOrderedSet<NSString *> *directories = [NSMutableOrderedSet orderedSetWithObject:[self inProgressDirectory]];
    [directories addObject:defaultStagingDirectory];
    for (NSString *directory in directories) {
        NSArray<NSString *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil];
        for (NSString *name in files) {
            if (![name.pathExtension.lowercaseString isEqualToString:@"mov"]) continue;
            NSURL *url = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:name]];
            AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
            BOOL playable = asset.playable && CMTIME_IS_NUMERIC(asset.duration) && CMTimeGetSeconds(asset.duration) > 0.05;
            NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:nil];
            JWRLog(@"recovery scan directory=%@ file=%@ bytes=%@ playable=%d duration=%.3f",
                   directory, name, attributes[NSFileSize], playable, CMTimeGetSeconds(asset.duration));
            if (playable) {
                NSURL *recoveredURL = nil;
                [self finalizeStagedVideoAtURL:url recovered:YES finalURL:&recoveredURL];
            } else {
                unsigned long long bytes = [attributes[NSFileSize] unsignedLongLongValue];
                if (bytes < JWRMinimumPlayableMovieBytes) {
                    NSError *removeError = nil;
                    [[NSFileManager defaultManager] removeItemAtURL:url error:&removeError];
                    JWRLog(@"removed header-only staged movie path=%@ bytes=%llu error=%@", url.path, bytes, removeError);
                } else {
                    JWRLog(@"retained nontrivial staged movie for manual recovery path=%@ bytes=%llu", url.path, bytes);
                }
            }
        }
    }
}
- (void)recoverPendingRecordings {
    dispatch_async(self.queue, ^{ [self recoverStagedVideosIfNeeded]; });
}
- (AVCaptureDevice *)camera {
    JWRPreferences *p = [JWRPreferences shared];
    AVCaptureDevicePosition pos = p.cameraPosition == 1 ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
    AVCaptureDeviceType type = (p.zoom < 1.0 && pos == AVCaptureDevicePositionBack) ? AVCaptureDeviceTypeBuiltInUltraWideCamera : AVCaptureDeviceTypeBuiltInWideAngleCamera;
    AVCaptureDevice *d = [AVCaptureDevice defaultDeviceWithDeviceType:type mediaType:AVMediaTypeVideo position:pos];
    if (!d && type == AVCaptureDeviceTypeBuiltInUltraWideCamera) {
        JWRLog(@"requested 0.5x camera is unsupported; falling back to the 1x camera");
        d = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:pos];
    }
    return d ?: [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
}
- (CMVideoDimensions)requestedVideoDimensions {
    NSInteger quality = [JWRPreferences shared].videoQuality;
    if (quality == -1) return (CMVideoDimensions){640, 480};
    if (quality == 0) return (CMVideoDimensions){1280, 720};
    if (quality == 2) return (CMVideoDimensions){3840, 2160};
    return (CMVideoDimensions){1920, 1080};
}
- (void)configureFormatForCamera:(AVCaptureDevice *)camera error:(NSError **)error {
    CMVideoDimensions requested = [self requestedVideoDimensions];
    double requestedFPS = MAX(1, [JWRPreferences shared].fps);
    AVCaptureDeviceFormat *bestFormat = nil;
    AVFrameRateRange *bestRange = nil;
    long long bestScore = LLONG_MIN;
    for (AVCaptureDeviceFormat *format in camera.formats) {
        CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
        long long pixelDifference = llabs((long long)dimensions.width * dimensions.height - (long long)requested.width * requested.height);
        BOOL exactResolution = dimensions.width == requested.width && dimensions.height == requested.height;
        for (AVFrameRateRange *range in format.videoSupportedFrameRateRanges) {
            BOOL supportsRequestedFPS = requestedFPS >= range.minFrameRate - 0.01 && requestedFPS <= range.maxFrameRate + 0.01;
            long long score = (exactResolution ? 1000000000000LL : 0) +
                              (supportsRequestedFPS ? 100000000000LL : 0) -
                              pixelDifference +
                              (long long)(range.maxFrameRate * 1000.0);
            if (score > bestScore) {
                bestScore = score;
                bestFormat = format;
                bestRange = range;
            }
        }
    }
    if (!bestFormat || !bestRange) {
        JWRLog(@"no camera format available");
        return;
    }
    camera.activeFormat = bestFormat;
    double actualFPS = MIN(MAX(requestedFPS, bestRange.minFrameRate), bestRange.maxFrameRate);
    CMTime frameDuration = CMTimeMake(1000, (int32_t)llround(actualFPS * 1000.0));
    camera.activeVideoMinFrameDuration = frameDuration;
    camera.activeVideoMaxFrameDuration = frameDuration;
    CMVideoDimensions actual = CMVideoFormatDescriptionGetDimensions(bestFormat.formatDescription);
    JWRLog(@"camera format requested=%dx%d@%.0f actual=%dx%d@%.2f supportedRange=%.2f-%.2f",
           requested.width, requested.height, requestedFPS, actual.width, actual.height, actualFPS,
           bestRange.minFrameRate, bestRange.maxFrameRate);
}
- (BOOL)prepareSession:(BOOL)withAudio {
    if (self.session) { JWRLog(@"reusing capture session"); return YES; }
    [self recoverStagedVideosIfNeeded];
    JWRLog(@"preparing capture session withAudio=%d", withAudio);
    AVCaptureSession *s = [AVCaptureSession new];
    s.sessionPreset = AVCaptureSessionPresetInputPriority;
    NSError *err; AVCaptureDevice *cam = [self camera];
    AVCaptureDeviceInput *ci = [AVCaptureDeviceInput deviceInputWithDevice:cam error:&err];
    if (!ci || ![s canAddInput:ci]) { JWRLog(@"camera input failed error=%@", err); return NO; }
    [s addInput:ci];
    if ([cam lockForConfiguration:&err]) {
        [self configureFormatForCamera:cam error:&err];
        if (cam.deviceType == AVCaptureDeviceTypeBuiltInWideAngleCamera)
            cam.videoZoomFactor = MAX(1.0, MIN(cam.activeFormat.videoMaxZoomFactor, [JWRPreferences shared].zoom));
        [cam unlockForConfiguration];
    } else JWRLog(@"camera configuration lock failed error=%@", err);
    if (withAudio) {
        AVCaptureDevice *mic = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
        AVCaptureDeviceInput *mi = [AVCaptureDeviceInput deviceInputWithDevice:mic error:nil];
        if (mi && [s canAddInput:mi]) [s addInput:mi];
        else JWRLog(@"microphone input unavailable");
    }
    self.movieOutput = [AVCaptureMovieFileOutput new];
    self.movieOutput.movieFragmentInterval = CMTimeMakeWithSeconds(2.0, 600);
    if ([s canAddOutput:self.movieOutput]) [s addOutput:self.movieOutput];
    self.photoOutput = [AVCapturePhotoOutput new]; if ([s canAddOutput:self.photoOutput]) [s addOutput:self.photoOutput];
    self.session = s;
    __weak typeof(self) weakSelf = self;
    self.sessionErrorObserver = [NSNotificationCenter.defaultCenter addObserverForName:AVCaptureSessionRuntimeErrorNotification object:s queue:nil usingBlock:^(NSNotification *note) {
        NSError *runtimeError = note.userInfo[AVCaptureSessionErrorKey];
        JWRLog(@"capture runtime error=%@", runtimeError);
        dispatch_async(weakSelf.queue, ^{
            if (weakSelf.desiredVideoRecording) [weakSelf requestVideoRecovery:[NSString stringWithFormat:@"runtime error %@", runtimeError]];
            else [weakSelf teardownCaptureSession];
        });
    }];
    self.sessionInterruptedObserver = [NSNotificationCenter.defaultCenter addObserverForName:AVCaptureSessionWasInterruptedNotification object:s queue:nil usingBlock:^(NSNotification *note) {
        JWRLog(@"capture interrupted reason=%@ userInfo=%@", note.userInfo[AVCaptureSessionInterruptionReasonKey], note.userInfo);
    }];
    self.sessionInterruptionEndedObserver = [NSNotificationCenter.defaultCenter addObserverForName:AVCaptureSessionInterruptionEndedNotification object:s queue:nil usingBlock:^(NSNotification *note) {
        JWRLog(@"capture interruption ended");
        dispatch_async(weakSelf.queue, ^{
            if (weakSelf.desiredVideoRecording && (!weakSelf.session.running || !weakSelf.movieOutput.recording))
                [weakSelf requestVideoRecovery:@"capture interruption ended without active recording"];
        });
    }];
    if (@available(iOS 16.0, *)) {
        JWRLog(@"multitasking camera supported=%d enabled=%d", s.multitaskingCameraAccessSupported, s.multitaskingCameraAccessEnabled);
        if (s.multitaskingCameraAccessSupported) {
            s.multitaskingCameraAccessEnabled = YES;
            JWRLog(@"multitasking camera enabled now=%d", s.multitaskingCameraAccessEnabled);
        }
    }
    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 18) {
        // iOS 18 grants background camera only while an active video-chat
        // audio session is running (the video-call continuation rule).
        // AVCaptureSession's automatic config selects videoRecording mode,
        // which loses the camera ~126ms after backgrounding.
        s.automaticallyConfiguresApplicationAudioSession = NO;
        NSError *audioSessionError = nil;
        AVAudioSession *audioSession = AVAudioSession.sharedInstance;
        BOOL configured = [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord
                                                mode:AVAudioSessionModeVideoChat
                                             options:AVAudioSessionCategoryOptionDefaultToSpeaker
                                               error:&audioSessionError];
        BOOL activated = configured && [audioSession setActive:YES error:&audioSessionError];
        self.videoChatAudioSessionActive = activated;
        JWRLog(@"videoChat audio session configured=%d active=%d mode=%@ error=%@",
               configured, activated, audioSession.mode, audioSessionError);
    }
    [s startRunning];
    JWRLog(@"capture startRunning returned running=%d interrupted=%d", s.running, s.interrupted);
    return YES;
}
- (void)feedbackNotification:(NSString *)notification {
    if ([JWRPreferences shared].haptics) notify_post(notification.UTF8String);
    notify_post(JWRNotifyState.UTF8String);
}
- (void)failureFeedback:(NSString *)reason {
    JWRLog(@"recording health failure: %@", reason);
    [self feedbackNotification:JWRNotifyHapticFailure];
}
- (void)cancelHeartbeatTimer {
    if (self.heartbeatTimer) {
        dispatch_source_cancel(self.heartbeatTimer);
        self.heartbeatTimer = nil;
    }
}
- (void)scheduleHeartbeatTimer {
    [self cancelHeartbeatTimer];
    NSInteger interval = [JWRPreferences shared].recordingHeartbeatInterval;
    if (interval <= 0 || (!self.desiredVideoRecording && !self.desiredAudioRecording)) return;
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, interval * NSEC_PER_SEC),
                              interval * NSEC_PER_SEC, NSEC_PER_SEC);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(timer, ^{
        typeof(self) self = weakSelf;
        BOOL healthyVideo = self.desiredVideoRecording && self.session.running && self.movieOutput.recording;
        BOOL healthyAudio = self.desiredAudioRecording && self.audioRecorder.recording;
        if (healthyVideo || healthyAudio) {
            JWRLog(@"recording heartbeat healthy video=%d audio=%d", healthyVideo, healthyAudio);
            [self feedbackNotification:JWRNotifyHapticHeartbeat];
        }
    });
    self.heartbeatTimer = timer;
    dispatch_resume(timer);
    JWRLog(@"scheduled recording heartbeat every %ld seconds", (long)interval);
}
- (void)refreshHealthMonitoring {
    dispatch_async(self.queue, ^{
        [self scheduleHeartbeatTimer];
        if (self.desiredVideoRecording) {
            [self scheduleWatchdogTimer];
            [self scheduleSegmentTimerIfNeeded];
        }
    });
}
- (void)cancelWatchdogTimer {
    if (self.watchdogTimer) {
        dispatch_source_cancel(self.watchdogTimer);
        self.watchdogTimer = nil;
    }
}
- (void)scheduleWatchdogTimer {
    [self cancelWatchdogTimer];
    if (!self.desiredVideoRecording) return;
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                              5 * NSEC_PER_SEC, NSEC_PER_SEC / 2);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(timer, ^{
        typeof(self) self = weakSelf;
        if (!self || !self.desiredVideoRecording || self.rollingSegment || self.recoveryInProgress) return;
        if (!self.session.running || !self.movieOutput.recording) {
            [self requestVideoRecovery:[NSString stringWithFormat:@"watchdog detected session=%d output=%d",
                                        self.session.running, self.movieOutput.recording]];
        }
    });
    self.watchdogTimer = timer;
    dispatch_resume(timer);
    JWRLog(@"video watchdog scheduled every 5 seconds");
}
- (void)teardownCaptureSession {
    [self cancelSegmentTimer];
    if (self.session.running) [self.session stopRunning];
    if (self.videoChatAudioSessionActive && !self.desiredAudioRecording) {
        NSError *deactivationError = nil;
        BOOL deactivated = [AVAudioSession.sharedInstance setActive:NO error:&deactivationError];
        JWRLog(@"videoChat audio session deactivated=%d error=%@", deactivated, deactivationError);
        self.videoChatAudioSessionActive = NO;
    }
    if (self.sessionErrorObserver) [NSNotificationCenter.defaultCenter removeObserver:self.sessionErrorObserver];
    if (self.sessionInterruptedObserver) [NSNotificationCenter.defaultCenter removeObserver:self.sessionInterruptedObserver];
    if (self.sessionInterruptionEndedObserver) [NSNotificationCenter.defaultCenter removeObserver:self.sessionInterruptionEndedObserver];
    self.sessionErrorObserver = nil;
    self.sessionInterruptedObserver = nil;
    self.sessionInterruptionEndedObserver = nil;
    self.session = nil;
    self.movieOutput = nil;
    self.photoOutput = nil;
    self.videoRecording = NO;
}
- (void)cancelSegmentTimer {
    if (self.segmentTimer) {
        dispatch_source_cancel(self.segmentTimer);
        self.segmentTimer = nil;
    }
}
- (void)scheduleSegmentTimerIfNeeded {
    [self cancelSegmentTimer];
    NSInteger duration = [JWRPreferences shared].videoSegmentDurationSeconds;
    if (duration <= 0 || !self.videoRecording) return;
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, duration * NSEC_PER_SEC), DISPATCH_TIME_FOREVER, NSEC_PER_SEC / 10);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(timer, ^{
        typeof(self) self = weakSelf;
        if (!self || !self.videoRecording || !self.movieOutput.recording) return;
        JWRLog(@"custom segment boundary reached after %ld seconds; finalizing %@", (long)duration, self.videoURL.lastPathComponent);
        self.rollingSegment = YES;
        [self.movieOutput stopRecording];
    });
    self.segmentTimer = timer;
    dispatch_resume(timer);
    JWRLog(@"scheduled next video segment boundary in %ld seconds", (long)duration);
}
- (AVMutableMetadataItem *)metadataItem:(AVMetadataIdentifier)identifier value:(id<NSObject, NSCopying>)value {
    AVMutableMetadataItem *item = [AVMutableMetadataItem metadataItem];
    item.identifier = identifier;
    item.value = value;
    return item;
}
- (void)applyVideoMetadata {
    NSMutableArray<AVMetadataItem *> *metadata = [NSMutableArray array];
    NSISO8601DateFormatter *dateFormatter = [NSISO8601DateFormatter new];
    [metadata addObject:[self metadataItem:AVMetadataIdentifierQuickTimeMetadataCreationDate value:[dateFormatter stringFromDate:NSDate.date]]];
    [metadata addObject:[self metadataItem:AVMetadataIdentifierQuickTimeMetadataMake value:@"Apple"]];
    [metadata addObject:[self metadataItem:AVMetadataIdentifierQuickTimeMetadataModel value:UIDevice.currentDevice.model]];
    [metadata addObject:[self metadataItem:AVMetadataIdentifierQuickTimeMetadataSoftware value:@"JimWas Recorder 2.0.1"]];
    if ([JWRPreferences shared].embedLocationMetadata) {
        NSDictionary *location = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Documents/JimWasRecorder/location.plist"];
        NSTimeInterval age = NSDate.date.timeIntervalSince1970 - [location[@"timestamp"] doubleValue];
        if (location && age >= 0 && age < 900) {
            double latitude = [location[@"latitude"] doubleValue];
            double longitude = [location[@"longitude"] doubleValue];
            double altitude = [location[@"altitude"] doubleValue];
            NSString *iso6709 = [NSString stringWithFormat:@"%+.6f%+.6f%+.1f/", latitude, longitude, altitude];
            [metadata addObject:[self metadataItem:AVMetadataIdentifierQuickTimeMetadataLocationISO6709 value:iso6709]];
            [metadata addObject:[self metadataItem:AVMetadataIdentifierQuickTimeMetadataLocationHorizontalAccuracyInMeters value:location[@"horizontalAccuracy"] ?: @0]];
            JWRLog(@"embedding video GPS metadata %@ age=%.1fs", iso6709, age);
        } else {
            JWRLog(@"GPS metadata enabled but no fresh cached location is available age=%.1fs", age);
        }
    }
    self.movieOutput.metadata = metadata;
}
- (void)scheduleHealthyRecordingConfirmationForOutput:(AVCaptureMovieFileOutput *)output {
    NSUInteger generation = ++self.recordingGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(JWRHealthyRecordingConfirmationDelay * NSEC_PER_SEC)), self.queue, ^{
        typeof(self) self = weakSelf;
        if (!self || generation != self.recordingGeneration || !self.desiredVideoRecording || output != self.movieOutput) return;
        NSTimeInterval recordedSeconds = CMTIME_IS_NUMERIC(output.recordedDuration) ? CMTimeGetSeconds(output.recordedDuration) : 0;
        if (self.session.running && output.recording && isfinite(recordedSeconds) && recordedSeconds >= 1.0) {
            NSInteger previousAttempts = self.recoveryAttempts;
            self.recoveryAttempts = 0;
            JWRLog(@"video recording confirmed healthy duration=%.3f previousRecoveryFailures=%ld",
                   recordedSeconds, (long)previousAttempts);
        } else {
            JWRLog(@"video health confirmation pending session=%d output=%d duration=%.3f failures=%ld",
                   self.session.running, output.recording, recordedSeconds, (long)self.recoveryAttempts);
        }
    });
}
- (void)beginVideoRecording {
    if (!self.desiredVideoRecording) return;
    if (![self prepareSession:YES]) {
        [self failureFeedback:@"video start aborted because the capture session is unavailable"];
        [self retryVideoRecoveryAfterDelay];
        return;
    }
    [self prepareVideoURLs];
    [self applyVideoMetadata];
    BOOL recoveredStart = self.recoveryInProgress;
    void (^startMovie)(void) = ^{
        if (!self.desiredVideoRecording) return;
        if (!self.session.running) {
            [self requestVideoRecovery:@"capture session did not become ready"];
            return;
        }
        [self.movieOutput startRecordingToOutputFileURL:self.videoURL recordingDelegate:self];
        self.videoRecording = YES;
        self.recoveryInProgress = NO;
        JWRLog(@"video+audio recording started url=%@", self.videoURL.path);
        [self scheduleHealthyRecordingConfirmationForOutput:self.movieOutput];
        [self scheduleSegmentTimerIfNeeded];
        [self scheduleWatchdogTimer];
        [self scheduleHeartbeatTimer];
        if (!recoveredStart) [self feedbackNotification:JWRNotifyHapticVideoStarted];
        else JWRLog(@"video watchdog recovery restarted recording");
    };
    if (self.session.running) startMovie();
    else dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), self.queue, startMovie);
}
- (void)retryVideoRecoveryAfterDelay {
    if (!self.desiredVideoRecording) return;
    self.recoveryInProgress = YES;
    self.recoveryAttempts++;
    if (self.recoveryAttempts >= JWRMaximumConsecutiveRecoveryFailures) {
        JWRLog(@"video recovery circuit breaker opened after %ld consecutive failures", (long)self.recoveryAttempts);
        self.desiredVideoRecording = NO;
        self.recoveryInProgress = NO;
        self.rollingSegment = NO;
        self.recordingGeneration++;
        [self cancelSegmentTimer];
        [self cancelWatchdogTimer];
        [self cancelHeartbeatTimer];
        [self teardownCaptureSession];
        [self failureFeedback:@"recording disabled after repeated camera failures; check debug.log before trying again"];
        return;
    }
    NSTimeInterval delay = MIN(30.0, pow(2.0, (double)self.recoveryAttempts));
    NSUInteger retryGeneration = ++self.recordingGeneration;
    JWRLog(@"video recovery attempt=%ld scheduled in %.1fs", (long)self.recoveryAttempts, delay);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), self.queue, ^{
        if (!self.desiredVideoRecording || retryGeneration != self.recordingGeneration) return;
        [self teardownCaptureSession];
        [self beginVideoRecording];
    });
}
- (void)requestVideoRecovery:(NSString *)reason {
    if (!self.desiredVideoRecording || self.recoveryInProgress) return;
    self.recoveryInProgress = YES;
    [self failureFeedback:reason];
    [self cancelSegmentTimer];
    AVCaptureMovieFileOutput *failedOutput = self.movieOutput;
    if (failedOutput.recording) {
        JWRLog(@"stopping current movie before watchdog recovery");
        [failedOutput stopRecording];
    } else {
        [self teardownCaptureSession];
        [self retryVideoRecoveryAfterDelay];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC), self.queue, ^{
        if (self.desiredVideoRecording && self.recoveryInProgress && self.movieOutput == failedOutput) {
            JWRLog(@"watchdog recovery stop timed out; forcing capture-session rebuild");
            [self teardownCaptureSession];
            [self retryVideoRecoveryAfterDelay];
        }
    });
}
- (void)toggleVideo { dispatch_async(self.queue, ^{
    JWRLog(@"toggleVideo current=%d desired=%d", self.videoRecording, self.desiredVideoRecording);
    if (self.desiredVideoRecording) {
        self.desiredVideoRecording = NO;
        self.recoveryInProgress = NO;
        self.rollingSegment = NO;
        self.recordingGeneration++;
        [self cancelSegmentTimer];
        [self cancelWatchdogTimer];
        if (self.movieOutput.recording) [self.movieOutput stopRecording];
        else {
            [self teardownCaptureSession];
            [self cancelHeartbeatTimer];
            [self feedbackNotification:JWRNotifyHapticVideoStopped];
        }
        return;
    }
    self.desiredVideoRecording = YES;
    self.recoveryAttempts = 0;
    [self beginVideoRecording];
}); }
- (void)captureOutput:(AVCaptureFileOutput *)output didFinishRecordingToOutputFileAtURL:(NSURL *)url fromConnections:(NSArray *)connections error:(NSError *)error {
    dispatch_async(self.queue, ^{
        BOOL isCurrentOutput = output == self.movieOutput;
        BOOL successfullyFinished = !error || [error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] boolValue];
        BOOL wasRolling = isCurrentOutput && self.rollingSegment;
        BOOL wasRecovering = isCurrentOutput && self.recoveryInProgress;
        if (isCurrentOutput) self.rollingSegment = NO;
        JWRLog(@"video segment finished url=%@ error=%@ successful=%d current=%d rolling=%d recovering=%d desired=%d",
               url.path, error, successfullyFinished, isCurrentOutput, wasRolling, wasRecovering, self.desiredVideoRecording);

        NSURL *finishedURL = nil;
        BOOL finalized = successfullyFinished && [self finalizeStagedVideoAtURL:url recovered:NO finalURL:&finishedURL];
        if (finalized) [self handleFinalizedVideoAtURL:finishedURL context:@"video segment"];
        if (!isCurrentOutput) return;

        if (self.desiredVideoRecording && (!successfullyFinished || !finalized)) {
            [self failureFeedback:[NSString stringWithFormat:@"video segment did not finalize error=%@", error]];
        }
        if (self.desiredVideoRecording && wasRolling && successfullyFinished && finalized) {
            [self prepareVideoURLs];
            [self applyVideoMetadata];
            [self.movieOutput startRecordingToOutputFileURL:self.videoURL recordingDelegate:self];
            self.videoRecording = YES;
            JWRLog(@"next crash-safe video+audio segment started url=%@", self.videoURL.path);
            [self scheduleHealthyRecordingConfirmationForOutput:self.movieOutput];
            [self scheduleSegmentTimerIfNeeded];
            return;
        }
        if (self.desiredVideoRecording) {
            if (!wasRecovering) [self failureFeedback:@"recording stopped unexpectedly; watchdog will restart it"];
            [self teardownCaptureSession];
            [self retryVideoRecoveryAfterDelay];
            return;
        }
        [self teardownCaptureSession];
        [self cancelHeartbeatTimer];
        [self feedbackNotification:JWRNotifyHapticVideoStopped];
    });
}
- (NSError *)audioVideoError:(NSString *)description {
    return [NSError errorWithDomain:@"com.jimwas.recorder.audio-video"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey:description ?: @"Audio video conversion failed."}];
}
- (void)handleFinalizedVideoAtURL:(NSURL *)finishedURL context:(NSString *)context {
    if (!finishedURL) return;
    NSInteger storageMode = [JWRPreferences shared].videoStorageMode;
    if (storageMode == 0) {
        JWRLog(@"%@ retained in save folder path=%@", context, finishedURL.path);
        return;
    }
    BOOL deleteAfterImport = storageMode == 1;
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:finishedURL];
    } completionHandler:^(BOOL success, NSError *photosError) {
        dispatch_async(self.queue, ^{
            JWRLog(@"%@ Photos import completed success=%d photosOnly=%d error=%@", context, success, deleteAfterImport, photosError);
            if (!success) {
                [self failureFeedback:[NSString stringWithFormat:@"%@ could not save to Camera Roll; local fallback retained error=%@", context, photosError]];
                return;
            }
            if (!deleteAfterImport) return;
            NSError *removeError = nil;
            BOOL removed = [[NSFileManager defaultManager] removeItemAtURL:finishedURL error:&removeError];
            JWRLog(@"%@ Photos-only local cleanup path=%@ removed=%d error=%@", context, finishedURL.path, removed, removeError);
            if (!removed && removeError) {
                [self failureFeedback:[NSString stringWithFormat:@"%@ saved to Camera Roll but local cleanup failed error=%@", context, removeError]];
            }
        });
    }];
}
- (void)finishAudioVideoConversionAtURL:(NSURL *)stagedURL
                               audioURL:(NSURL *)audioURL
                                success:(BOOL)success
                                  error:(NSError *)error {
    dispatch_async(self.queue, ^{
        if (!success) {
            if (stagedURL) [[NSFileManager defaultManager] removeItemAtURL:stagedURL error:nil];
            JWRLog(@"audio video copy failed audio=%@ staged=%@ error=%@", audioURL.path, stagedURL.path, error);
            [self failureFeedback:[NSString stringWithFormat:@"audio video copy failed error=%@", error]];
            return;
        }
        NSURL *finishedURL = nil;
        BOOL finalized = [self finalizeStagedVideoAtURL:stagedURL recovered:NO finalURL:&finishedURL];
        if (!finalized) {
            [self failureFeedback:@"audio video copy could not be finalized"];
            return;
        }
        JWRLog(@"audio video copy finalized audio=%@ video=%@", audioURL.path, finishedURL.path);
        [self handleFinalizedVideoAtURL:finishedURL context:@"audio video copy"];
    });
}
- (void)createVideoCopyForAudioURL:(NSURL *)audioURL {
    if (!audioURL) return;
    AVURLAsset *audioAsset = [AVURLAsset URLAssetWithURL:audioURL options:nil];
    AVAssetTrack *audioTrack = [audioAsset tracksWithMediaType:AVMediaTypeAudio].firstObject;
    CMTime duration = audioAsset.duration;
    if (!audioTrack || !CMTIME_IS_NUMERIC(duration) || CMTimeGetSeconds(duration) <= 0.01) {
        [self finishAudioVideoConversionAtURL:nil audioURL:audioURL success:NO
                                       error:[self audioVideoError:@"The audio recording has no readable audio track."]];
        return;
    }

    NSString *stagingDirectory = [self inProgressDirectory];
    NSError *directoryError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:stagingDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&directoryError];
    if (directoryError) {
        [self finishAudioVideoConversionAtURL:nil audioURL:audioURL success:NO error:directoryError];
        return;
    }
    NSString *baseName = audioURL.URLByDeletingPathExtension.lastPathComponent;
    NSURL *stagedURL = [NSURL fileURLWithPath:
        [stagingDirectory stringByAppendingPathComponent:[baseName stringByAppendingPathExtension:@"mov"]]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:stagedURL.path]) {
        stagedURL = [NSURL fileURLWithPath:[stagingDirectory stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@_%@.mov", baseName, NSUUID.UUID.UUIDString]]];
    }

    NSURL *templateURL = [NSBundle.mainBundle URLForResource:@"JWRBlackVideo" withExtension:@"mov"];
    AVURLAsset *templateAsset = templateURL ? [AVURLAsset URLAssetWithURL:templateURL options:nil] : nil;
    AVAssetTrack *templateTrack = [templateAsset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    CMTime templateDuration = templateAsset.duration;
    if (!templateTrack || !CMTIME_IS_NUMERIC(templateDuration) || CMTimeGetSeconds(templateDuration) <= 0.01) {
        [self finishAudioVideoConversionAtURL:stagedURL audioURL:audioURL success:NO
                                       error:[self audioVideoError:@"The bundled black-video template is unavailable."]];
        return;
    }

    AVMutableComposition *composition = [AVMutableComposition composition];
    AVMutableCompositionTrack *compositionAudio =
        [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
    AVMutableCompositionTrack *compositionVideo =
        [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    NSError *compositionError = nil;
    BOOL insertedAudio = [compositionAudio insertTimeRange:CMTimeRangeMake(kCMTimeZero, duration)
                                                  ofTrack:audioTrack
                                                   atTime:kCMTimeZero
                                                    error:&compositionError];
    BOOL insertedVideo = [compositionVideo insertTimeRange:CMTimeRangeMake(kCMTimeZero, templateDuration)
                                                  ofTrack:templateTrack
                                                   atTime:kCMTimeZero
                                                    error:&compositionError];
    if (!insertedAudio || !insertedVideo || compositionError) {
        [self finishAudioVideoConversionAtURL:stagedURL audioURL:audioURL success:NO
                                       error:compositionError ?: [self audioVideoError:@"Could not assemble the audio-video composition."]];
        return;
    }
    [compositionVideo scaleTimeRange:CMTimeRangeMake(kCMTimeZero, templateDuration) toDuration:duration];
    compositionVideo.preferredTransform = templateTrack.preferredTransform;

    AVAssetExportSession *exporter =
        [[AVAssetExportSession alloc] initWithAsset:composition presetName:AVAssetExportPresetPassthrough];
    if (!exporter || ![exporter.supportedFileTypes containsObject:AVFileTypeQuickTimeMovie]) {
        [self finishAudioVideoConversionAtURL:stagedURL audioURL:audioURL success:NO
                                       error:[self audioVideoError:@"QuickTime passthrough export is unavailable."]];
        return;
    }
    exporter.outputURL = stagedURL;
    exporter.outputFileType = AVFileTypeQuickTimeMovie;
    exporter.shouldOptimizeForNetworkUse = YES;
    exporter.metadata = @[
        [self metadataItem:AVMetadataIdentifierQuickTimeMetadataCreationDate
                     value:[[NSISO8601DateFormatter new] stringFromDate:NSDate.date]],
        [self metadataItem:AVMetadataIdentifierQuickTimeMetadataSoftware value:@"JimWas Recorder 2.0.1"],
        [self metadataItem:AVMetadataIdentifierQuickTimeMetadataModel value:@"Audio-only black video"]
    ];
    JWRLog(@"audio video passthrough export started audio=%@ staged=%@ duration=%.3f",
           audioURL.path, stagedURL.path, CMTimeGetSeconds(duration));
    [exporter exportAsynchronouslyWithCompletionHandler:^{
        BOOL success = exporter.status == AVAssetExportSessionStatusCompleted;
        [self finishAudioVideoConversionAtURL:stagedURL audioURL:audioURL
                                      success:success error:exporter.error];
    }];
}
- (void)toggleAudio { dispatch_async(self.queue, ^{
    JWRLog(@"toggleAudio current=%d", self.audioRecording);
    if (self.desiredAudioRecording) {
        self.desiredAudioRecording = NO;
        [self.audioRecorder stop];
        self.audioRecording = NO;
        [self cancelHeartbeatTimer];
        [self feedbackNotification:JWRNotifyHapticStopped];
        return;
    }
    self.desiredAudioRecording = YES;
    AVAudioSession *as = AVAudioSession.sharedInstance;
    NSError *sessionError;
    [as setCategory:AVAudioSessionCategoryPlayAndRecord mode:AVAudioSessionModeDefault options:AVAudioSessionCategoryOptionMixWithOthers|AVAudioSessionCategoryOptionDefaultToSpeaker error:&sessionError];
    if (sessionError) JWRLog(@"audio category error=%@", sessionError);
    sessionError = nil;
    [as setActive:YES withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&sessionError];
    if (sessionError) JWRLog(@"audio activation error=%@", sessionError);
    NSDictionary *settings = @{AVFormatIDKey:@(kAudioFormatMPEG4AAC), AVSampleRateKey:@44100, AVNumberOfChannelsKey:@1, AVEncoderAudioQualityKey:@(AVAudioQualityHigh)};
    NSError *recorderError;
    self.audioRecorder = [[AVAudioRecorder alloc] initWithURL:[self outputURLWithExtension:@"m4a"] settings:settings error:&recorderError];
    if (recorderError) JWRLog(@"audio recorder init error=%@", recorderError);
    self.audioRecorder.delegate = self;
    self.audioRecording = [self.audioRecorder record];
    JWRLog(@"audio record result=%d url=%@", self.audioRecording, self.audioRecorder.url.path);
    if (self.audioRecording) {
        [self scheduleHeartbeatTimer];
        [self feedbackNotification:JWRNotifyHapticStarted];
    } else {
        self.desiredAudioRecording = NO;
        [self failureFeedback:[NSString stringWithFormat:@"audio recording failed to start error=%@", recorderError]];
    }
}); }
- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)flag {
    dispatch_async(self.queue, ^{
        JWRLog(@"audio recorder finished successfully=%d desired=%d", flag, self.desiredAudioRecording);
        self.audioRecording = NO;
        if (flag && [JWRPreferences shared].saveAudioAsVideo) {
            [self createVideoCopyForAudioURL:recorder.url];
        }
        if (self.desiredAudioRecording) {
            self.desiredAudioRecording = NO;
            [self cancelHeartbeatTimer];
            [self failureFeedback:@"audio recording stopped unexpectedly"];
        }
    });
}
- (void)audioRecorderEncodeErrorDidOccur:(AVAudioRecorder *)recorder error:(NSError *)error {
    dispatch_async(self.queue, ^{
        JWRLog(@"audio recorder encode error=%@", error);
        if (self.desiredAudioRecording) {
            self.desiredAudioRecording = NO;
            self.audioRecording = NO;
            [self cancelHeartbeatTimer];
            [self failureFeedback:[NSString stringWithFormat:@"audio encoding failed error=%@", error]];
        }
    });
}
- (void)takePhoto { dispatch_async(self.queue, ^{
    JWRLog(@"takePhoto requested");
    if (![self prepareSession:NO]) { JWRLog(@"photo aborted: session unavailable"); return; }
    AVCapturePhotoSettings *settings = [AVCapturePhotoSettings photoSettings];
    settings.photoQualityPrioritization = AVCapturePhotoQualityPrioritizationQuality;
    [self.photoOutput capturePhotoWithSettings:settings delegate:self];
}); }
- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(NSError *)error {
    JWRLog(@"photo processing finished error=%@", error);
    NSData *data = [photo fileDataRepresentation]; if (!data) { JWRLog(@"photo had no data"); return; }
    NSURL *url = [self outputURLWithExtension:@"jpg"];
    UIImage *image = [UIImage imageWithData:data];
    NSData *jpeg = UIImageJPEGRepresentation(image, [JWRPreferences shared].photoQuality);
    NSError *writeError; [jpeg writeToURL:url options:NSDataWritingAtomic error:&writeError];
    JWRLog(@"photo write url=%@ bytes=%lu error=%@", url.path, (unsigned long)jpeg.length, writeError);
    if (!writeError) [self feedbackNotification:JWRNotifyHapticPhoto];
    if ([JWRPreferences shared].savePhotoToPhotos)
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{ [PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:url]; } completionHandler:nil];
    dispatch_async(self.queue, ^{ if (!self.videoRecording) { [self.session stopRunning]; self.session = nil; } });
}
@end
