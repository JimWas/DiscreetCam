#import <UIKit/UIKit.h>
#import <notify.h>
#import "../JWRLogger.h"
#import "../JWRConstants.h"

@interface CCUIToggleModule : NSObject
- (void)refreshState;
@end
@interface JWRVideoModule : CCUIToggleModule
@property(nonatomic) BOOL selected;
@end

static int JWRStateToken;
static __weak JWRVideoModule *JWRSharedVideoModule;

@implementation JWRVideoModule
+ (void)load {
    notify_register_dispatch(JWRNotifyState.UTF8String, &JWRStateToken, dispatch_get_main_queue(), ^(int token) {
        JWRVideoModule *module = JWRSharedVideoModule;
        if (!module) return;
        uint64_t state = 0;
        notify_get_state(token, &state);
        BOOL active = (state & JWRStateVideoActive) != 0;
        if (module->_selected != active) {
            module->_selected = active;
            [module refreshState];
        }
    });
}
- (instancetype)init {
    if ((self = [super init])) {
        JWRSharedVideoModule = self;
        uint64_t state = 0;
        notify_get_state(JWRStateToken, &state);
        _selected = (state & JWRStateVideoActive) != 0;
    }
    return self;
}
- (UIImage *)iconGlyph { return [UIImage systemImageNamed:@"video.fill"]; }
- (UIImage *)selectedIconGlyph { return [UIImage systemImageNamed:@"video.fill"]; }
- (UIColor *)selectedColor { return UIColor.systemRedColor; }
- (BOOL)isSelected { return self.selected; }
- (void)setSelected:(BOOL)selected {
    _selected = selected;
    JWRLog(@"Control Center video tapped selected=%d", selected);
    // Route through the shared trigger receiver so the Enabled/lock gate in
    // SpringBoard applies on every firmware, not only iOS 18.
    notify_post(JWRNotifyTriggerVideo.UTF8String);
    [self refreshState];
    // Snap back to the recorder's actual state when the gate denied the tap
    // (recorder disabled or screen locked) after a slow real start has posted.
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        typeof(self) self = weakSelf;
        if (!self) return;
        uint64_t state = 0;
        notify_get_state(JWRStateToken, &state);
        BOOL active = (state & JWRStateVideoActive) != 0;
        if (self->_selected != active) {
            self->_selected = active;
            [self refreshState];
        }
    });
}
@end
