#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <CoreLocation/CoreLocation.h>
#import "../JWRLogger.h"

@interface JWRAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic) UIWindow *window;
@property(nonatomic) CLLocationManager *locationManager;
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
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title,status,button]];
    stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 24; stack.alignment = UIStackViewAlignmentCenter; stack.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],[stack.centerYAnchor constraintEqualToAnchor:vc.view.centerYAnchor],[stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:vc.view.leadingAnchor constant:24],[stack.trailingAnchor constraintLessThanOrEqualToAnchor:vc.view.trailingAnchor constant:-24]]];
    self.window.rootViewController = vc; [self.window makeKeyAndVisible]; [self updateStatus];
    return YES;
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
    JWRLog(@"permission status camera=%@ microphone=%@ photos=%@ location=%@", camera, mic, photos, location);
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
- (void)applicationDidEnterBackground:(UIApplication *)application { JWRLog(@"app entered background"); }
- (void)applicationWillEnterForeground:(UIApplication *)application { JWRLog(@"app entering foreground"); }
- (void)applicationWillTerminate:(UIApplication *)application { JWRLog(@"app will terminate"); }
@end
