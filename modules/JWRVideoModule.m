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

static BOOL JWRUsesForegroundCameraHost(void) {
    return NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 18;
}

@implementation JWRVideoModule
- (UIImage *)iconGlyph { return [UIImage systemImageNamed:@"video.fill"]; }
- (UIImage *)selectedIconGlyph { return [UIImage systemImageNamed:@"video.fill"]; }
- (UIColor *)selectedColor { return UIColor.systemRedColor; }
- (BOOL)isSelected { return self.selected; }
- (void)setSelected:(BOOL)selected {
    _selected = selected;
    JWRLog(@"Control Center video tapped selected=%d", selected);
    // iOS 18 has no toggleVideo receiver; the trigger notification routes
    // through SpringBoard, which foregrounds the companion app first.
    if (JWRUsesForegroundCameraHost())
        notify_post(JWRNotifyTriggerVideo.UTF8String);
    else
        notify_post(JWRNotifyVideo.UTF8String);
    [self refreshState];
}
@end
