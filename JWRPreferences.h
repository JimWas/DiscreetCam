#import <Foundation/Foundation.h>
#import "JWRConstants.h"

@interface JWRPreferences : NSObject
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL triggersWhileLocked;
@property(nonatomic) BOOL triggersWhileAudioPlaying;
@property(nonatomic) BOOL haptics;
@property(nonatomic) NSInteger recordingHeartbeatInterval;
@property(nonatomic) BOOL saveVideoToPhotos;
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
@property(nonatomic) JWRAction doubleVolumeUpAction;
@property(nonatomic) JWRAction doubleVolumeDownAction;
@property(nonatomic) JWRAction longVolumeUpAction;
@property(nonatomic) JWRAction longVolumeDownAction;
@property(nonatomic) JWRAction bothVolumesAction;
@property(nonatomic) JWRAction powerAction;
+ (instancetype)shared;
- (void)reload;
@end
