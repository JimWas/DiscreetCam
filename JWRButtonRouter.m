#import "JWRButtonRouter.h"
#import "JWRPreferences.h"
#import "JWRLogger.h"
#import <notify.h>
#ifdef GNUSTEP
#import <Block.h>
#endif

static const NSTimeInterval JWRDoubleTapWindow = 0.38;
static const NSTimeInterval JWRLongPressDelay = 0.70;

static BOOL JWRIsDeviceLocked(void) {
    Class c = NSClassFromString(@"SBLockScreenManager");
    id m = [c respondsToSelector:@selector(sharedInstance)] ? [c performSelector:@selector(sharedInstance)] : nil;
    if (!m || ![m respondsToSelector:@selector(isUILocked)]) return NO;
    return [[m valueForKey:@"isUILocked"] boolValue];
}

@implementation JWRButtonRouter
@synthesize preferences;
@synthesize lastUp;
@synthesize lastDown;
@synthesize upHeld;
@synthesize downHeld;
#ifndef GNUSTEP
@synthesize now;
@synthesize isDeviceLocked;
@synthesize usesForegroundCameraHost;
@synthesize performAfterDelay;
@synthesize runAction;
@synthesize postNotification;
#else
// The GNUstep runtime (libobjc4 + libBlocksRuntime 0.4.1) cannot copy blocks
// (Block_copy segfaults), so the seam blocks are stored by plain assignment.
// This is safe because the harness creates and uses the router within one
// stack frame; the on-device ARC build uses the synthesized copy accessors.
- (NSTimeInterval (^)(void))now {
    return now;
}
- (void)setNow:(NSTimeInterval (^)(void))value {
    now = value;
}
- (BOOL (^)(void))isDeviceLocked {
    return isDeviceLocked;
}
- (void)setIsDeviceLocked:(BOOL (^)(void))value {
    isDeviceLocked = value;
}
- (BOOL (^)(void))usesForegroundCameraHost {
    return usesForegroundCameraHost;
}
- (void)setUsesForegroundCameraHost:(BOOL (^)(void))value {
    usesForegroundCameraHost = value;
}
- (void (^)(NSTimeInterval, void (^)(void)))performAfterDelay {
    return performAfterDelay;
}
- (void)setPerformAfterDelay:(void (^)(NSTimeInterval, void (^)(void)))value {
    performAfterDelay = value;
}
- (void (^)(JWRAction))runAction {
    return runAction;
}
- (void)setRunAction:(void (^)(JWRAction))value {
    runAction = value;
}
- (void (^)(NSString *))postNotification {
    return postNotification;
}
- (void)setPostNotification:(void (^)(NSString *))value {
    postNotification = value;
}
#endif

+ (instancetype)shared {
    static JWRButtonRouter *router; static dispatch_once_t once;
    dispatch_once(&once, ^{ router = [self new]; });
    return router;
}
- (instancetype)init {
    if ((self = [super init])) {
        self.preferences = [JWRPreferences shared];
        self.now = ^NSTimeInterval {
#ifdef GNUSTEP
            return [NSDate timeIntervalSinceReferenceDate];
#else
            return NSProcessInfo.processInfo.systemUptime;
#endif
        };
        self.isDeviceLocked = ^BOOL { return JWRIsDeviceLocked(); };
        self.usesForegroundCameraHost = ^BOOL {
#ifdef GNUSTEP
            return NO; // GNUstep has no NSOperatingSystemVersion; tests inject the seam
#else
            return NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 18;
#endif
        };
        self.performAfterDelay = ^(NSTimeInterval delay, void (^block)(void)) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
        };
        self.postNotification = ^(NSString *name) { notify_post(name.UTF8String); };
        self.runAction = nil;
    }
    return self;
}
- (void)reset {
    self.lastUp = 0;
    self.lastDown = 0;
    self.upHeld = NO;
    self.downHeld = NO;
}
- (void)buttonPressedUp {
    JWRPreferences *p = self.preferences;
    NSTimeInterval now = self.now();
    if (self.downHeld) {
        [self routeAction:p.bothVolumesAction];
        self.upHeld = NO;
        self.downHeld = NO;
        return;
    }
    self.upHeld = YES;
    if (now - self.lastUp < JWRDoubleTapWindow) [self routeAction:p.doubleVolumeUpAction];
    self.lastUp = now;
    __unsafe_unretained typeof(self) weakSelf = self;
    self.performAfterDelay(JWRLongPressDelay, ^{
        typeof(self) self = weakSelf;
        if (!self || !self.upHeld) return;
        self.upHeld = NO;
        [self routeAction:p.longVolumeUpAction];
    });
}
- (void)buttonPressedDown {
    JWRPreferences *p = self.preferences;
    NSTimeInterval now = self.now();
    if (self.upHeld) {
        [self routeAction:p.bothVolumesAction];
        self.upHeld = NO;
        self.downHeld = NO;
        return;
    }
    self.downHeld = YES;
    if (now - self.lastDown < JWRDoubleTapWindow) [self routeAction:p.doubleVolumeDownAction];
    self.lastDown = now;
    __unsafe_unretained typeof(self) weakSelf = self;
    self.performAfterDelay(JWRLongPressDelay, ^{
        typeof(self) self = weakSelf;
        if (!self || !self.downHeld) return;
        self.downHeld = NO;
        [self routeAction:p.longVolumeDownAction];
    });
}
- (void)buttonReleasedUp {
    self.upHeld = NO;
}
- (void)buttonReleasedDown {
    self.downHeld = NO;
}
- (BOOL)shouldDeliverAction:(JWRAction)action {
    JWRPreferences *p = self.preferences;
    if (!p.enabled) return NO;
    if (!p.triggersWhileLocked && self.isDeviceLocked()) return NO;
    return action != JWRActionNone;
}
- (void)routeAction:(JWRAction)action {
    if (self.runAction) {
        self.runAction(action);
        return;
    }
    if (![self shouldDeliverAction:action]) {
        JWRLog(@"trigger ignored action=%ld", (long)action);
        return;
    }
    JWRLog(@"sending trigger action=%ld", (long)action);
    if (action == JWRActionVideo && self.usesForegroundCameraHost()) [self launchForegroundCameraHost:JWRNotifyForegroundVideo];
    else if (action == JWRActionPhoto && self.usesForegroundCameraHost()) [self launchForegroundCameraHost:JWRNotifyForegroundPhoto];
    else if (action == JWRActionVideo) self.postNotification(JWRNotifyVideo);
    else if (action == JWRActionAudio) self.postNotification(JWRNotifyAudio);
    else if (action == JWRActionPhoto) self.postNotification(JWRNotifyPhoto);
}
- (void)launchForegroundCameraHost:(NSString *)notification {
    // openApplicationWithBundleID: only launches when called on SpringBoard's
    // main thread, where it blocks ~10s (iOS 18.1.1 has no async variant).
    // Delegate the launch to the service daemon, which can call it freely.
    NSString *launch = [notification isEqualToString:JWRNotifyForegroundPhoto]
        ? JWRNotifyLaunchCameraPhoto : JWRNotifyLaunchCameraVideo;
    self.postNotification(launch);
    JWRLog(@"camera host launch delegated to service (%@)", launch);
}
@end
