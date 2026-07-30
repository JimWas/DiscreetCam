#import "JWRLocationProvider.h"
#import "JWRPreferences.h"
#import "JWRLogger.h"
#import <CoreLocation/CoreLocation.h>

@interface JWRLocationProvider () <CLLocationManagerDelegate>
@property(nonatomic) CLLocationManager *manager;
@end

@implementation JWRLocationProvider
+ (instancetype)shared {
    static JWRLocationProvider *provider; static dispatch_once_t once;
    dispatch_once(&once, ^{ provider = [self new]; });
    return provider;
}
- (void)updateForPreferences {
    if (![JWRPreferences shared].embedLocationMetadata) {
        [self.manager stopUpdatingLocation];
        JWRLog(@"location metadata disabled");
        return;
    }
    if (!self.manager) {
        self.manager = [CLLocationManager new];
        self.manager.delegate = self;
        self.manager.desiredAccuracy = kCLLocationAccuracyBest;
        self.manager.distanceFilter = 5.0;
        self.manager.pausesLocationUpdatesAutomatically = NO;
        self.manager.allowsBackgroundLocationUpdates = YES;
    }
    [self.manager startUpdatingLocation];
    JWRLog(@"location updates started authorization=%ld", (long)self.manager.authorizationStatus);
}
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *location = locations.lastObject;
    if (!location || location.horizontalAccuracy < 0) return;
    NSDictionary *data = @{@"latitude":@(location.coordinate.latitude),
                           @"longitude":@(location.coordinate.longitude),
                           @"altitude":@(location.altitude),
                           @"horizontalAccuracy":@(location.horizontalAccuracy),
                           @"verticalAccuracy":@(location.verticalAccuracy),
                           @"timestamp":@(location.timestamp.timeIntervalSince1970)};
    [data writeToFile:@"/var/mobile/Documents/JimWasRecorder/location.plist" atomically:YES];
    JWRLog(@"location cache updated lat=%.6f lon=%.6f accuracy=%.1fm", location.coordinate.latitude, location.coordinate.longitude, location.horizontalAccuracy);
}
- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    JWRLog(@"location update failed error=%@", error);
}
@end
