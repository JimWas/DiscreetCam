#import <UIKit/UIKit.h>
#import <notify.h>
#import "../JWRConstants.h"
#import "../JWRRecorderManager.h"
#import "../JWRPreferences.h"
#import "../JWRLogger.h"
#import "../JWRLocationProvider.h"

@interface JWRAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic) UIWindow *window;
@end

static void RunService(void) {
    @autoreleasepool {
        JWRLog(@"service starting");
        [JWRPreferences shared];
        [[JWRLocationProvider shared] updateForPreferences];
        static int a, r;
        dispatch_queue_t q = dispatch_get_main_queue();
        notify_register_dispatch(JWRNotifyAudio.UTF8String, &a, q, ^(int t){ JWRLog(@"received audio toggle"); [[JWRRecorderManager shared] toggleAudio]; });
        notify_register_dispatch(JWRNotifyReload.UTF8String, &r, q, ^(int t){
            JWRLog(@"received preference reload");
            [[JWRPreferences shared] reload];
            [[JWRLocationProvider shared] updateForPreferences];
            [[JWRRecorderManager shared] refreshHealthMonitoring];
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
