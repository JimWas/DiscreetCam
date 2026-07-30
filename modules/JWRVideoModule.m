#import <UIKit/UIKit.h>
#import <notify.h>
#import "../JWRLogger.h"

@interface CCUIToggleModule : NSObject
- (void)refreshState;
@end
@interface JWRVideoModule : CCUIToggleModule
@property(nonatomic) BOOL selected;
@end
@implementation JWRVideoModule
- (UIImage *)iconGlyph { return [UIImage systemImageNamed:@"video.fill"]; }
- (UIImage *)selectedIconGlyph { return [UIImage systemImageNamed:@"video.fill"]; }
- (UIColor *)selectedColor { return UIColor.systemRedColor; }
- (BOOL)isSelected { return self.selected; }
- (void)setSelected:(BOOL)selected {
    _selected = selected;
    JWRLog(@"Control Center video tapped selected=%d", selected);
    notify_post("com.jimwas.recorder/toggleVideo");
    [self refreshState];
}
@end
