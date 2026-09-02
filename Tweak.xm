#import <UIKit/UIKit.h>
#import <notify.h>
#import <objc/message.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFAudio/AVAudioSession.h>
#import <dlfcn.h>
#import "JWRPreferences.h"
#import "JWRLogger.h"
#import "JWRRecorderManager.h"

static NSTimeInterval lastUp = 0, lastDown = 0;
static BOOL upHeld = NO, downHeld = NO;
static int reloadToken, videoToken, photoToken, triggerVideoToken, hapticStartedToken, hapticStoppedToken, hapticPhotoToken, hapticHeartbeatToken, hapticFailureToken, hapticVideoStartedToken, hapticVideoStoppedToken;
static float lastObservedSystemVolume = -1.0f;
static id systemVolumeObserver;

static BOOL JWRUsesForegroundCameraHost(void) {
    return NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 18;
}

static void JWRLaunchForegroundCameraHost(NSString *notification) {
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL defaultSelector = NSSelectorFromString(@"defaultWorkspace");
    SEL openSelector = NSSelectorFromString(@"openApplicationWithBundleID:");
    id workspace = workspaceClass && [workspaceClass respondsToSelector:defaultSelector]
        ? ((id (*)(id, SEL))objc_msgSend)(workspaceClass, defaultSelector) : nil;
    BOOL opened = workspace && [workspace respondsToSelector:openSelector]
        ? ((BOOL (*)(id, SEL, id))objc_msgSend)(workspace, openSelector, @"com.jimwas.recorder.app") : NO;
    JWRLog(@"iOS 18 foreground camera host launch opened=%d notification=%@", opened, notification);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1200 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        notify_post(notification.UTF8String);
    });
}

static void JWRPlayReliableVibration(void) {
    AudioServicesPlayAlertSound(kSystemSoundID_Vibrate);
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
    [generator prepare];
    if ([generator respondsToSelector:@selector(impactOccurredWithIntensity:)])
        [generator impactOccurredWithIntensity:1.0];
    else
        [generator impactOccurred];
}

static void JWRPlayStrongVideoVibration(BOOL started) {
    typedef void (*JWRVibrationFunction)(SystemSoundID, id, NSDictionary *);
    static JWRVibrationFunction vibrationFunction;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        vibrationFunction = (JWRVibrationFunction)dlsym(RTLD_DEFAULT, "AudioServicesPlaySystemSoundWithVibration");
        JWRLog(@"strong vibration API available=%d", vibrationFunction != NULL);
    });
    if (vibrationFunction) {
        NSArray *pattern = started
            ? @[@YES, @360, @NO, @180, @YES, @360]
            : @[@YES, @650];
        vibrationFunction(4095, nil, @{@"VibePattern": pattern, @"Intensity": @1.0});
        JWRPlayReliableVibration();
        if (started) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 420 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ JWRPlayReliableVibration(); });
        return;
    }
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
    [generator prepare];
    if ([generator respondsToSelector:@selector(impactOccurredWithIntensity:)])
        [generator impactOccurredWithIntensity:1.0];
    else
        [generator impactOccurred];
    AudioServicesPlaySystemSound(1520);
    JWRPlayReliableVibration();
    if (started) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 360 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            UIImpactFeedbackGenerator *secondGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
            [secondGenerator prepare];
            [secondGenerator impactOccurred];
            AudioServicesPlaySystemSound(1520);
            JWRPlayReliableVibration();
        });
    }
}

static BOOL JWRLocked(void) {
    Class c = NSClassFromString(@"SBLockScreenManager");
    id m = [c respondsToSelector:@selector(sharedInstance)] ? [c performSelector:@selector(sharedInstance)] : nil;
    return m && [m respondsToSelector:@selector(isUILocked)] && ((BOOL (*)(id,SEL))objc_msgSend)(m, @selector(isUILocked));
}
static void JWRRun(JWRAction action) {
    JWRPreferences *p = [JWRPreferences shared];
    if (!p.enabled || (!p.triggersWhileLocked && JWRLocked())) { JWRLog(@"trigger ignored action=%ld", (long)action); return; }
    JWRLog(@"sending trigger action=%ld", (long)action);
    if (action == JWRActionVideo && JWRUsesForegroundCameraHost()) JWRLaunchForegroundCameraHost(JWRNotifyForegroundVideo);
    else if (action == JWRActionPhoto && JWRUsesForegroundCameraHost()) JWRLaunchForegroundCameraHost(JWRNotifyForegroundPhoto);
    else if (action == JWRActionVideo) notify_post(JWRNotifyVideo.UTF8String);
    else if (action == JWRActionAudio) notify_post(JWRNotifyAudio.UTF8String);
    else if (action == JWRActionPhoto) notify_post(JWRNotifyPhoto.UTF8String);
}
static void JWRButton(BOOL up) {
    JWRPreferences *p = [JWRPreferences shared];
    NSTimeInterval now = CACurrentMediaTime();
    if (up) {
        if (downHeld) { JWRRun(p.bothVolumesAction); upHeld = downHeld = NO; return; }
        upHeld = YES;
        if (now - lastUp < 0.38) JWRRun(p.doubleVolumeUpAction);
        lastUp = now;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, .7*NSEC_PER_SEC), dispatch_get_main_queue(), ^{ if (upHeld) { upHeld=NO; JWRRun(p.longVolumeUpAction); } });
    } else {
        if (upHeld) { JWRRun(p.bothVolumesAction); upHeld = downHeld = NO; return; }
        downHeld = YES;
        if (now - lastDown < 0.38) JWRRun(p.doubleVolumeDownAction);
        lastDown = now;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, .7*NSEC_PER_SEC), dispatch_get_main_queue(), ^{ if (downHeld) { downHeld=NO; JWRRun(p.longVolumeDownAction); } });
    }
}

%hook SBVolumeControl
- (void)increaseVolume { if (!JWRUsesForegroundCameraHost()) JWRButton(YES); %orig; dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.15*NSEC_PER_SEC),dispatch_get_main_queue(),^{upHeld=NO;}); }
- (void)decreaseVolume { if (!JWRUsesForegroundCameraHost()) JWRButton(NO); %orig; dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.15*NSEC_PER_SEC),dispatch_get_main_queue(),^{downHeld=NO;}); }
%end

%hook SBLiftToWakeManager
- (void)liftToWakeController:(id)controller didObserveTransition:(long long)transition deviceOrientation:(long long)orientation {
    if ([JWRPreferences shared].preventWakeWhileRecording && [JWRRecorderManager shared].videoRecording) {
        JWRLog(@"suppressed raise-to-wake during video recording");
        return;
    }
    %orig;
}
%end

%hook SBLockScreenManager
- (void)_wakeScreenForTapToWake {
    if ([JWRPreferences shared].preventWakeWhileRecording && [JWRRecorderManager shared].videoRecording) {
        JWRLog(@"suppressed tap-to-wake during video recording");
        return;
    }
    %orig;
}
%end

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    JWRLog(@"SpringBoard trigger component loaded");
    [[JWRRecorderManager shared] recoverPendingRecordings];
    if (!JWRUsesForegroundCameraHost()) {
        notify_register_dispatch(JWRNotifyVideo.UTF8String, &videoToken, dispatch_get_main_queue(), ^(int t){
            JWRLog(@"SpringBoard received video toggle");
            [[JWRRecorderManager shared] toggleVideo];
        });
        notify_register_dispatch(JWRNotifyPhoto.UTF8String, &photoToken, dispatch_get_main_queue(), ^(int t){
            JWRLog(@"SpringBoard received photo request");
            [[JWRRecorderManager shared] takePhoto];
        });
    } else {
        JWRLog(@"iOS 18 foreground companion camera mode enabled");
        lastObservedSystemVolume = [AVAudioSession sharedInstance].outputVolume;
        systemVolumeObserver = [NSNotificationCenter.defaultCenter addObserverForName:@"AVSystemController_SystemVolumeDidChangeNotification" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            NSNumber *value = note.userInfo[@"AVSystemController_AudioVolumeNotificationParameter"];
            if (!value) return;
            float newVolume = value.floatValue;
            float oldVolume = lastObservedSystemVolume;
            lastObservedSystemVolume = newVolume;
            if (oldVolume < 0.0f || fabsf(newVolume - oldVolume) < 0.0001f) return;
            BOOL up = newVolume > oldVolume;
            JWRLog(@"iOS 18 volume notification direction=%@ old=%.3f new=%.3f reason=%@", up ? @"up" : @"down", oldVolume, newVolume, note.userInfo[@"AVSystemController_AudioVolumeChangeReasonNotificationParameter"]);
            JWRButton(up);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                if (up) upHeld = NO; else downHeld = NO;
            });
        }];
        notify_register_dispatch(JWRNotifyTriggerVideo.UTF8String, &triggerVideoToken, dispatch_get_main_queue(), ^(int token) {
            JWRLog(@"received diagnostic video trigger");
            JWRRun(JWRActionVideo);
        });
    }
    notify_register_dispatch(JWRNotifyHapticStarted.UTF8String, &hapticStartedToken, dispatch_get_main_queue(), ^(int t){
        if (![JWRPreferences shared].haptics) return;
        AudioServicesPlaySystemSound(1520);
        JWRPlayReliableVibration();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 160 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ AudioServicesPlaySystemSound(1520); });
        JWRLog(@"played recording-started double haptic");
    });
    notify_register_dispatch(JWRNotifyHapticStopped.UTF8String, &hapticStoppedToken, dispatch_get_main_queue(), ^(int t){
        if (![JWRPreferences shared].haptics) return;
        AudioServicesPlaySystemSound(1520);
        JWRPlayReliableVibration();
        JWRLog(@"played recording-stopped haptic");
    });
    notify_register_dispatch(JWRNotifyHapticPhoto.UTF8String, &hapticPhotoToken, dispatch_get_main_queue(), ^(int t){
        if (![JWRPreferences shared].haptics) return;
        AudioServicesPlaySystemSound(1519);
        JWRPlayReliableVibration();
        JWRLog(@"played photo-captured haptic");
    });
    notify_register_dispatch(JWRNotifyHapticHeartbeat.UTF8String, &hapticHeartbeatToken, dispatch_get_main_queue(), ^(int t){
        if (![JWRPreferences shared].haptics) return;
        AudioServicesPlaySystemSound(1519);
        JWRLog(@"played recording heartbeat haptic");
    });
    notify_register_dispatch(JWRNotifyHapticFailure.UTF8String, &hapticFailureToken, dispatch_get_main_queue(), ^(int t){
        if (![JWRPreferences shared].haptics) return;
        AudioServicesPlaySystemSound(1521);
        JWRPlayReliableVibration();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 140 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ AudioServicesPlaySystemSound(1521); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 280 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ AudioServicesPlaySystemSound(1521); });
        JWRLog(@"played recording-failure triple haptic");
    });
    notify_register_dispatch(JWRNotifyHapticVideoStarted.UTF8String, &hapticVideoStartedToken, dispatch_get_main_queue(), ^(int t){
        if (![JWRPreferences shared].haptics) return;
        JWRPlayStrongVideoVibration(YES);
        JWRLog(@"played video-started SE2-compatible strong vibration pattern");
    });
    notify_register_dispatch(JWRNotifyHapticVideoStopped.UTF8String, &hapticVideoStoppedToken, dispatch_get_main_queue(), ^(int t){
        if (![JWRPreferences shared].haptics) return;
        JWRPlayStrongVideoVibration(NO);
        JWRLog(@"played video-stopped SE2-compatible strong vibration pattern");
    });
    notify_register_dispatch(JWRNotifyReload.UTF8String, &reloadToken, dispatch_get_main_queue(), ^(int t){
        [[JWRPreferences shared] reload];
        [[JWRRecorderManager shared] refreshHealthMonitoring];
    });
}
%end

%ctor { @autoreleasepool { [JWRPreferences shared]; } }
