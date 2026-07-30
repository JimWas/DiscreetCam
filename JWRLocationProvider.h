#import <Foundation/Foundation.h>

@interface JWRLocationProvider : NSObject
+ (instancetype)shared;
- (void)updateForPreferences;
@end
