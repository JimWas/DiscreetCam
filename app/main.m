#import <UIKit/UIKit.h>
#import <notify.h>
#import <dlfcn.h>
#import <objc/message.h>
#import "../JWRConstants.h"
#import "../JWRRecorderManager.h"
#import "../JWRPreferences.h"
#import "../JWRLogger.h"
#import "../JWRLocationProvider.h"

@interface JWRAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic) UIWindow *window;
@end

static void JWROpenCameraHostAndPost(NSString *toggle) {
    // LSApplicationWorkspace silently refuses off-main-thread callers, so this
    // runs on the daemon's main thread; blocking ~10s during a cold launch is
    // fine for a headless service.
    // LSApplicationWorkspace is not linked into this binary; load it on demand.
    dlopen("/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_LAZY);
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL defaultSelector = NSSelectorFromString(@"defaultWorkspace");
    SEL openSelector = NSSelectorFromString(@"openApplicationWithBundleID:");
    id workspace = workspaceClass && [workspaceClass respondsToSelector:defaultSelector]
        ? ((id (*)(id, SEL))objc_msgSend)(workspaceClass, defaultSelector) : nil;
    BOOL opened = workspace && [workspace respondsToSelector:openSelector]
        ? ((BOOL (*)(id, SEL, id))objc_msgSend)(workspace, openSelector, @"com.jimwas.recorder.app") : NO;
    JWRLog(@"service opened camera host opened=%d toggle=%@", opened, toggle);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1200 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        notify_post(toggle.UTF8String);
    });
}

static void RunService(void) {
    @autoreleasepool {
        JWRLog(@"service starting");
        [JWRPreferences shared];
        [[JWRLocationProvider shared] updateForPreferences];
        static int a, r, lv, lp;
        dispatch_queue_t q = dispatch_get_main_queue();
        notify_register_dispatch(JWRNotifyAudio.UTF8String, &a, q, ^(int t){ JWRLog(@"received audio toggle"); [[JWRRecorderManager shared] toggleAudio]; });
        notify_register_dispatch(JWRNotifyReload.UTF8String, &r, q, ^(int t){
            JWRLog(@"received preference reload");
            [[JWRPreferences shared] reload];
            [[JWRLocationProvider shared] updateForPreferences];
            [[JWRRecorderManager shared] refreshHealthMonitoring];
        });
        notify_register_dispatch(JWRNotifyLaunchCameraVideo.UTF8String, &lv, q, ^(int t){
            JWRLog(@"service received camera video launch request");
            JWROpenCameraHostAndPost(JWRNotifyForegroundVideo);
        });
        notify_register_dispatch(JWRNotifyLaunchCameraPhoto.UTF8String, &lp, q, ^(int t){
            JWRLog(@"service received camera photo launch request");
            JWROpenCameraHostAndPost(JWRNotifyForegroundPhoto);
        });
        [[NSFileManager defaultManager] createFileAtPath:@"/var/mobile/Documents/.jwr-service-ready" contents:[NSData data] attributes:nil];
        CFRunLoopRun();
    }
}

int main(int argc, char *argv[]) {
    if (argc > 1 && strcmp(argv[1], "--post-video") == 0) { notify_post(JWRNotifyVideo.UTF8String); return 0; }
    if (argc > 1 && strcmp(argv[1], "--post-audio") == 0) { notify_post(JWRNotifyAudio.UTF8String); return 0; }
    if (argc > 1 && strcmp(argv[1], "--post-photo") == 0) { notify_post(JWRNotifyPhoto.UTF8String); return 0; }
    if (argc > 1 && strcmp(argv[1], "--post-foreground-video") == 0) { notify_post(JWRNotifyForegroundVideo.UTF8String); return 0; }
    if (argc > 1 && strcmp(argv[1], "--post-foreground-photo") == 0) { notify_post(JWRNotifyForegroundPhoto.UTF8String); return 0; }
    if (argc > 1 && strcmp(argv[1], "--trigger-video") == 0) { notify_post(JWRNotifyTriggerVideo.UTF8String); return 0; }
    if (argc > 1 && strcmp(argv[1], "--service") == 0) { RunService(); return 0; }
    @autoreleasepool { JWRLog(@"UI app starting"); return UIApplicationMain(argc, argv, nil, NSStringFromClass(JWRAppDelegate.class)); }
}
