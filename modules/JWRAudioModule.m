#import <UIKit/UIKit.h>
#import <notify.h>
#import "../JWRLogger.h"

@interface CCUIToggleModule : NSObject
- (void)refreshState;
@end
@interface JWRAudioModule : CCUIToggleModule
@property(nonatomic) BOOL selected;
@end
@implementation JWRAudioModule
- (UIImage *)iconGlyph { return [UIImage systemImageNamed:@"mic.fill"]; }
- (UIImage *)selectedIconGlyph { return [UIImage systemImageNamed:@"mic.fill"]; }
- (UIColor *)selectedColor { return UIColor.systemOrangeColor; }
- (BOOL)isSelected { return self.selected; }
- (void)setSelected:(BOOL)selected {
    _selected = selected;
    JWRLog(@"Control Center audio tapped selected=%d", selected);
    notify_post("com.jimwas.recorder/toggleAudio");
    [self refreshState];
}
@end
