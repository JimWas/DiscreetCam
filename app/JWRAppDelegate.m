#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <CoreLocation/CoreLocation.h>
#import <spawn.h>
#import <sys/wait.h>
#import <notify.h>
#import "../JWRLogger.h"
#import "../JWRConstants.h"
#import "../JWRRecorderManager.h"

extern char **environ;
static int foregroundVideoToken, foregroundPhotoToken;

@interface JWRAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic) UIWindow *window;
@property(nonatomic) CLLocationManager *locationManager;
@property(nonatomic) UITextView *diagnosticTextView;
@end

@implementation JWRAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    JWRLog(@"app did finish launching");
    self.locationManager = [CLLocationManager new];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.systemBackgroundColor;
    UILabel *title = [UILabel new]; title.text = @"JimWas Recorder"; title.font = [UIFont boldSystemFontOfSize:28]; title.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *status = [UILabel new]; status.tag = 100; status.numberOfLines = 0; status.textAlignment = NSTextAlignmentCenter; status.translatesAutoresizingMaskIntoConstraints = NO;
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem]; [button setTitle:@"Grant Recording Permissions" forState:UIControlStateNormal]; button.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold]; button.translatesAutoresizingMaskIntoConstraints = NO;
    [button addTarget:self action:@selector(requestPermissions:) forControlEvents:UIControlEventTouchUpInside];
    UIButton *resetButton = [UIButton buttonWithType:UIButtonTypeSystem]; [resetButton setTitle:@"Reset Recording Permissions" forState:UIControlStateNormal]; resetButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]; resetButton.translatesAutoresizingMaskIntoConstraints = NO;
    [resetButton addTarget:self action:@selector(confirmPermissionReset:) forControlEvents:UIControlEventTouchUpInside];
    UIButton *logButton = [UIButton buttonWithType:UIButtonTypeSystem]; [logButton setTitle:@"View Diagnostic Log" forState:UIControlStateNormal]; logButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]; logButton.translatesAutoresizingMaskIntoConstraints = NO;
    [logButton addTarget:self action:@selector(showDiagnosticLog:) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title,status,button,resetButton,logButton]];
    stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 24; stack.alignment = UIStackViewAlignmentCenter; stack.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],[stack.centerYAnchor constraintEqualToAnchor:vc.view.centerYAnchor],[stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:vc.view.leadingAnchor constant:24],[stack.trailingAnchor constraintLessThanOrEqualToAnchor:vc.view.trailingAnchor constant:-24]]];
    self.window.rootViewController = vc; [self.window makeKeyAndVisible]; [self updateStatus];
    notify_register_dispatch(JWRNotifyForegroundVideo.UTF8String, &foregroundVideoToken, dispatch_get_main_queue(), ^(int token) {
        JWRLog(@"companion received foreground video toggle appState=%ld", (long)application.applicationState);
        [[JWRRecorderManager shared] toggleVideo];
    });
    notify_register_dispatch(JWRNotifyForegroundPhoto.UTF8String, &foregroundPhotoToken, dispatch_get_main_queue(), ^(int token) {
        JWRLog(@"companion received foreground photo request appState=%ld", (long)application.applicationState);
        [[JWRRecorderManager shared] takePhoto];
    });
    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 18) {
        JWRLog(@"iOS 18 foreground camera receiver ready");
    }
    return YES;
}
- (NSString *)diagnosticLogText {
    NSArray<NSString *> *paths = @[@"/var/mobile/Library/Logs/JimWasRecorder/debug.log", @"/var/mobile/Documents/JimWasRecorder/debug.log", @"/tmp/JimWasRecorder/debug.log"];
    for (NSString *path in paths) {
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data.length) continue;
        NSUInteger start = data.length > 65536 ? data.length - 65536 : 0;
        NSData *tail = [data subdataWithRange:NSMakeRange(start, data.length - start)];
        NSString *text = [[NSString alloc] initWithData:tail encoding:NSUTF8StringEncoding];
        if (text.length) return [NSString stringWithFormat:@"Log: %@\n\n%@", path, text];
    }
    return @"No diagnostic log is available yet.";
}
- (void)showDiagnosticLog:(id)sender {
    JWRLog(@"diagnostic log viewer opened");
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.systemBackgroundColor;
    vc.title = @"Recorder Diagnostics";
    UITextView *textView = [UITextView new];
    textView.editable = NO; textView.selectable = YES; textView.alwaysBounceVertical = YES;
    textView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    textView.translatesAutoresizingMaskIntoConstraints = NO;
    self.diagnosticTextView = textView;
    UIButton *refresh = [UIButton buttonWithType:UIButtonTypeSystem]; [refresh setTitle:@"Refresh" forState:UIControlStateNormal]; [refresh addTarget:self action:@selector(refreshDiagnosticLog:) forControlEvents:UIControlEventTouchUpInside];
    UIButton *copy = [UIButton buttonWithType:UIButtonTypeSystem]; [copy setTitle:@"Copy Log" forState:UIControlStateNormal]; [copy addTarget:self action:@selector(copyDiagnosticLog:) forControlEvents:UIControlEventTouchUpInside];
    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem]; [done setTitle:@"Done" forState:UIControlStateNormal]; [done addTarget:self action:@selector(closeDiagnosticLog:) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[refresh, copy, done]];
    actions.axis = UILayoutConstraintAxisHorizontal; actions.distribution = UIStackViewDistributionFillEqually; actions.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:textView]; [vc.view addSubview:actions];
    UILayoutGuide *safe = vc.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[actions.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8], [actions.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12], [actions.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12], [actions.heightAnchor constraintEqualToConstant:44], [textView.topAnchor constraintEqualToAnchor:actions.bottomAnchor constant:8], [textView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:8], [textView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8], [textView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8]]];
    textView.text = [self diagnosticLogText];
    [self.window.rootViewController presentViewController:vc animated:YES completion:nil];
}
- (void)refreshDiagnosticLog:(id)sender { self.diagnosticTextView.text = [self diagnosticLogText]; JWRLog(@"diagnostic log refreshed"); }
- (void)copyDiagnosticLog:(id)sender { UIPasteboard.generalPasteboard.string = self.diagnosticTextView.text ?: @""; JWRLog(@"diagnostic log copied to pasteboard"); }
- (void)closeDiagnosticLog:(id)sender { [self.window.rootViewController dismissViewControllerAnimated:YES completion:^{ self.diagnosticTextView = nil; }]; }
- (int)runTCCUtilAtPath:(NSString *)path service:(NSString *)service {
    const char *tool = path.fileSystemRepresentation;
    char *const argv[] = {(char *)tool, "reset", (char *)service.UTF8String, "com.jimwas.recorder.app", NULL};
    pid_t pid = 0;
    int result = posix_spawn(&pid, tool, NULL, NULL, argv, environ);
    if (result != 0) return result;
    int status = 0;
    if (waitpid(pid, &status, 0) < 0) return -1;
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}
- (void)confirmPermissionReset:(id)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset permissions?" message:@"Camera, microphone, Photos, and location access will be cleared. You will need to grant them again." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) { [self resetPermissions]; }]];
    [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
}
- (void)resetPermissions {
    NSString *tool = [[NSFileManager defaultManager] isExecutableFileAtPath:@"/usr/bin/tccutil"] ? @"/usr/bin/tccutil" : @"/var/jb/usr/bin/tccutil";
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:tool]) {
        [self showResetResult:@"Permission reset is unavailable because tccutil was not found on this jailbreak."];
        return;
    }
    JWRLog(@"permission reset started tool=%@", tool);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<NSString *> *services = @[@"Camera", @"Microphone", @"Photos", @"Location"];
        NSMutableArray<NSString *> *failed = [NSMutableArray array];
        for (NSString *service in services) {
            int result = [self runTCCUtilAtPath:tool service:service];
            JWRLog(@"permission reset service=%@ result=%d", service, result);
            if (result != 0) [failed addObject:service];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateStatus];
            if (failed.count == 0) [self showResetResult:@"Permissions were reset. Tap Grant Recording Permissions to request them again."];
            else [self showResetResult:[NSString stringWithFormat:@"Could not reset: %@. Check the recorder debug log for details.", [failed componentsJoinedByString:@", "]]];
        });
    });
}
- (void)showResetResult:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"JimWas Recorder" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
}
- (void)updateStatus {
    UILabel *l = [self.window.rootViewController.view viewWithTag:100];
    NSString *camera = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] == AVAuthorizationStatusAuthorized ? @"Granted" : @"Not granted";
    NSString *mic = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio] == AVAuthorizationStatusAuthorized ? @"Granted" : @"Not granted";
    PHAuthorizationStatus ps = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelAddOnly];
    NSString *photos = (ps == PHAuthorizationStatusAuthorized || ps == PHAuthorizationStatusLimited) ? @"Granted" : @"Not granted";
    CLAuthorizationStatus ls = self.locationManager.authorizationStatus;
    NSString *location = ls == kCLAuthorizationStatusAuthorizedAlways ? @"Always" : (ls == kCLAuthorizationStatusAuthorizedWhenInUse ? @"While Using" : @"Not granted");
    l.text = [NSString stringWithFormat:@"Camera: %@\nMicrophone: %@\nPhotos: %@\nLocation: %@\n\nThe service runs separately from SpringBoard.", camera, mic, photos, location];
    BOOL serviceReady = [[NSFileManager defaultManager] fileExistsAtPath:@"/var/mobile/Documents/.jwr-service-ready"];
    JWRLog(@"permission status camera=%@(%ld) microphone=%@(%ld) photos=%@(%ld) location=%@(%d) appState=%ld serviceReady=%d", camera, (long)[AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo], mic, (long)[AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio], photos, (long)ps, location, (int)ls, (long)UIApplication.sharedApplication.applicationState, serviceReady);
}
- (void)requestPermissions:(id)sender {
    JWRLog(@"permission request started");
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL ok) {
        JWRLog(@"camera permission result=%d", ok);
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL ok2) {
            JWRLog(@"microphone permission result=%d", ok2);
            [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus s) {
                JWRLog(@"photos add permission result=%ld", (long)s);
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.locationManager = [CLLocationManager new];
                    [self.locationManager requestAlwaysAuthorization];
                    [self updateStatus];
                });
            }];
        }];
    }];
}
- (void)applicationDidBecomeActive:(UIApplication *)application { JWRLog(@"app became active"); [self updateStatus]; }
- (void)applicationWillResignActive:(UIApplication *)application { JWRLog(@"app will resign active"); }
- (void)applicationDidEnterBackground:(UIApplication *)application { JWRLog(@"app entered background backgroundTimeRemaining=%.1f", application.backgroundTimeRemaining); }
- (void)applicationWillEnterForeground:(UIApplication *)application { JWRLog(@"app entering foreground"); }
- (void)applicationWillTerminate:(UIApplication *)application { JWRLog(@"app will terminate"); }
@end
