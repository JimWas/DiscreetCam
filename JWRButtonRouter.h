#import <Foundation/Foundation.h>
#import "JWRConstants.h"

@class JWRPreferences;

@interface JWRButtonRouter : NSObject {
    JWRPreferences *preferences;
    NSTimeInterval (^now)(void);
    BOOL (^isDeviceLocked)(void);
    BOOL (^usesForegroundCameraHost)(void);
    void (^performAfterDelay)(NSTimeInterval, void (^)(void));
    void (^runAction)(JWRAction);
    void (^postNotification)(NSString *);
    NSTimeInterval lastUp;
    NSTimeInterval lastDown;
    BOOL upHeld;
    BOOL downHeld;
}
+ (instancetype)shared;

// Injectable seams; the defaults reproduce production trigger behavior.
@property(nonatomic) JWRPreferences *preferences;
@property(nonatomic, copy) NSTimeInterval (^now)(void);
@property(nonatomic, copy) BOOL (^isDeviceLocked)(void);
@property(nonatomic, copy) BOOL (^usesForegroundCameraHost)(void);
@property(nonatomic, copy) void (^performAfterDelay)(NSTimeInterval delay, void (^block)(void));
@property(nonatomic, copy) void (^runAction)(JWRAction action);
@property(nonatomic, copy) void (^postNotification)(NSString *name);
// Gesture state (read/write so the harness can assert on transitions).
@property(nonatomic) NSTimeInterval lastUp;
@property(nonatomic) NSTimeInterval lastDown;
@property(nonatomic) BOOL upHeld;
@property(nonatomic) BOOL downHeld;

- (void)reset;
- (void)buttonPressedUp;
- (void)buttonPressedDown;
- (void)buttonReleasedUp;
- (void)buttonReleasedDown;
- (BOOL)shouldDeliverAction:(JWRAction)action;
- (void)routeAction:(JWRAction)action;
@end
