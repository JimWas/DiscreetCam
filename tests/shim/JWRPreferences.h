// Harness-only shadow of the production JWRPreferences.h. The GNU runtime's
// fragile ABI (Ubuntu's libobjc4) cannot auto-create ivars for @synthesize
// unless they are declared in the primary @interface, and the production
// header must stay untouched for the on-device build. Keep this interface in
// sync with JWRPreferences.h (properties + defaults); it must win the include
// path inside tests only.
#import <Foundation/Foundation.h>
#import "JWRConstants.h"

@interface JWRPreferences : NSObject {
    BOOL enabled;
    BOOL triggersWhileLocked;
    BOOL triggersWhileAudioPlaying;
    BOOL haptics;
    NSInteger recordingHeartbeatInterval;
    NSInteger videoStorageMode;
    BOOL savePhotoToPhotos;
    BOOL saveAudioAsVideo;
    BOOL splitVideoEveryTwoMinutes;
    NSInteger videoSegmentDurationSeconds;
    BOOL embedLocationMetadata;
    BOOL preventWakeWhileRecording;
    NSInteger cameraPosition;
    CGFloat zoom;
    NSInteger fps;
    NSInteger videoQuality;
    CGFloat photoQuality;
    NSString *filenamePrefix;
    NSString *videoOutputDirectory;
    NSInteger doubleVolumeUpAction;
    NSInteger doubleVolumeDownAction;
    NSInteger longVolumeUpAction;
    NSInteger longVolumeDownAction;
    NSInteger bothVolumesAction;
    NSInteger powerAction;
}
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL triggersWhileLocked;
@property(nonatomic) BOOL triggersWhileAudioPlaying;
@property(nonatomic) BOOL haptics;
@property(nonatomic) NSInteger recordingHeartbeatInterval;
@property(nonatomic) NSInteger videoStorageMode;
@property(nonatomic) BOOL savePhotoToPhotos;
@property(nonatomic) BOOL saveAudioAsVideo;
@property(nonatomic) BOOL splitVideoEveryTwoMinutes;
@property(nonatomic) NSInteger videoSegmentDurationSeconds;
@property(nonatomic) BOOL embedLocationMetadata;
@property(nonatomic) BOOL preventWakeWhileRecording;
@property(nonatomic) NSInteger cameraPosition;
@property(nonatomic) CGFloat zoom;
@property(nonatomic) NSInteger fps;
@property(nonatomic) NSInteger videoQuality;
@property(nonatomic) CGFloat photoQuality;
@property(nonatomic, copy) NSString *filenamePrefix;
@property(nonatomic, copy) NSString *videoOutputDirectory;
@property(nonatomic) NSInteger doubleVolumeUpAction;
@property(nonatomic) NSInteger doubleVolumeDownAction;
@property(nonatomic) NSInteger longVolumeUpAction;
@property(nonatomic) NSInteger longVolumeDownAction;
@property(nonatomic) NSInteger bothVolumesAction;
@property(nonatomic) NSInteger powerAction;
+ (instancetype)shared;
- (void)reload;
@end
