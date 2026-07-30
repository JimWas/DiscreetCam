#import <Foundation/Foundation.h>

@interface JWRRecorderManager : NSObject
@property(nonatomic, readonly) BOOL videoRecording;
@property(nonatomic, readonly) BOOL audioRecording;
+ (instancetype)shared;
- (void)toggleVideo;
- (void)toggleAudio;
- (void)takePhoto;
- (void)recoverPendingRecordings;
- (void)refreshHealthMonitoring;
@end
