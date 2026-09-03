#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <notify.h>
#import "../JWRConstants.h"
#import "../JWRRecorderManager.h"
#import "../JWRPreferences.h"
#import "../JWRLogger.h"
#import "../JWRLocationProvider.h"

@interface JWRAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic) UIWindow *window;
@end

static void JWRServiceCleanup(int sig) {
    [[NSFileManager defaultManager] removeItemAtPath:@"/var/mobile/Documents/.jwr-service-ready" error:nil];
    JWRLog(@"service exiting with signal %d; removed .jwr-service-ready", sig);
    exit(0);
}

static void RunService(void) {
    @autoreleasepool {
        signal(SIGTERM, JWRServiceCleanup);
        signal(SIGINT, JWRServiceCleanup);
        signal(SIGQUIT, JWRServiceCleanup);
        atexit_b(^{
            [[NSFileManager defaultManager] removeItemAtPath:@"/var/mobile/Documents/.jwr-service-ready" error:nil];
        });

        JWRLog(@"service starting with multitasking camera access");

        // Install camera capture session hooks into this process
        [JWRRecorderManager installCaptureSessionHooks];

        // Initialize AVAudioSession for background audio
        NSError *audioSessionError = nil;
        AVAudioSession *session = [AVAudioSession sharedInstance];
        [session setCategory:AVAudioSessionCategoryPlayAndRecord
                       mode:AVAudioSessionModeDefault
                     options:AVAudioSessionCategoryOptionAllowBluetoothHFP |
                             AVAudioSessionCategoryOptionDefaultToSpeaker |
                             AVAudioSessionCategoryOptionMixWithOthers
                           error:&audioSessionError];
        if (audioSessionError) {
            JWRLog(@"audio session category error: %@", audioSessionError);
        } else {
            [session setActive:YES error:&audioSessionError];
            if (audioSessionError) {
                JWRLog(@"audio session activation error: %@", audioSessionError);
            } else {
                JWRLog(@"audio session initialized successfully");
            }
        }

        [JWRPreferences shared];
        [[JWRLocationProvider shared] updateForPreferences];

        // Verify AVFoundation is available in this process
        Class sessionClass = NSClassFromString(@"AVCaptureSession");
        JWRLog(@"AVCaptureSession class available in service: %d", sessionClass != nil);

        // Check multitasking camera support
        if (sessionClass) {
            if (@available(iOS 16.0, *)) {
                AVCaptureSession *testSession = [[AVCaptureSession alloc] init];
                JWRLog(@"multitaskingCameraAccessSupported: %d", testSession.multitaskingCameraAccessSupported);
                if (testSession.multitaskingCameraAccessSupported) {
                    testSession.multitaskingCameraAccessEnabled = YES;
                    JWRLog(@"multitaskingCameraAccessEnabled set to: %d", testSession.multitaskingCameraAccessEnabled);
                }
            }
        }

        static int v, vs, ve, a, p, r;
        dispatch_queue_t q = dispatch_get_main_queue();

        // Video recording notifications
        notify_register_dispatch(JWRNotifyVideo.UTF8String, &v, q, ^(int t){
            JWRLog(@"service received video toggle");
            [[JWRRecorderManager shared] toggleVideo];
        });
        notify_register_dispatch(JWRNotifyVideoStart.UTF8String, &vs, q, ^(int t){
            JWRLog(@"service received video start");
            [[JWRRecorderManager shared] startVideo];
        });
        notify_register_dispatch(JWRNotifyVideoStop.UTF8String, &ve, q, ^(int t){
            JWRLog(@"service received video stop");
            [[JWRRecorderManager shared] stopVideo];
        });

        // Audio recording notifications
        notify_register_dispatch(JWRNotifyAudio.UTF8String, &a, q, ^(int t){
            JWRLog(@"service received audio toggle");
            [[JWRRecorderManager shared] toggleAudio];
        });

        // Photo notifications
        notify_register_dispatch(JWRNotifyPhoto.UTF8String, &p, q, ^(int t){
            JWRLog(@"service received photo request");
            [[JWRRecorderManager shared] takePhoto];
        });

        // Reload preferences
        notify_register_dispatch(JWRNotifyReload.UTF8String, &r, q, ^(int t){
            JWRLog(@"service received preference reload");
            [[JWRPreferences shared] reload];
            [[JWRLocationProvider shared] updateForPreferences];
            [[JWRRecorderManager shared] refreshHealthMonitoring];
        });

        [[NSFileManager defaultManager] createFileAtPath:@"/var/mobile/Documents/.jwr-service-ready" contents:[NSData data] attributes:nil];
        JWRLog(@"service ready, waiting for notifications");
        CFRunLoopRun();
    }
}

int main(int argc, char *argv[]) {
    if (argc > 1 && strcmp(argv[1], "--post-video") == 0) { notify_post(JWRNotifyVideo.UTF8String); return 0; }
    if (argc > 1 && strcmp(argv[1], "--post-audio") == 0) { notify_post(JWRNotifyAudio.UTF8String); return 0; }
    if (argc > 1 && strcmp(argv[1], "--post-photo") == 0) { notify_post(JWRNotifyPhoto.UTF8String); return 0; }
    if (argc > 1 && strcmp(argv[1], "--service") == 0) { RunService(); return 0; }
    @autoreleasepool { JWRLog(@"UI app starting"); return UIApplicationMain(argc, argv, nil, NSStringFromClass(JWRAppDelegate.class)); }
}
