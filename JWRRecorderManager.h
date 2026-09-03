#import <Foundation/Foundation.h>

@interface JWRRecorderManager : NSObject
@property(nonatomic, readonly) BOOL videoRecording;
@property(nonatomic, readonly) BOOL audioRecording;
+ (instancetype)shared;
+ (BOOL)serviceProcessAvailable;
+ (void)installCaptureSessionHooks;
- (void)toggleVideo;
- (void)startVideo;
- (void)stopVideo;
- (void)toggleAudio;
- (void)takePhoto;
- (void)recoverPendingRecordings;
- (void)refreshHealthMonitoring;
@end
