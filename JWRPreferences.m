#import "JWRPreferences.h"
#import "JWRPreferences+Normalization.h"

@implementation JWRPreferences
+ (instancetype)shared {
    static JWRPreferences *p; static dispatch_once_t once;
    dispatch_once(&once, ^{ p = [self new]; [p reload]; });
    return p;
}
- (void)reload {
    CFPreferencesAppSynchronize((__bridge CFStringRef)JWRPrefsID);
    NSDictionary *d = (__bridge_transfer NSDictionary *)CFPreferencesCopyMultiple(NULL, (__bridge CFStringRef)JWRPrefsID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    id (^v)(NSString *, id) = ^id(NSString *key, id fallback) { return d[key] ?: fallback; };
    _enabled = [v(@"enabled", @YES) boolValue];
    _triggersWhileLocked = [v(@"triggersWhileLocked", @NO) boolValue];
    _triggersWhileAudioPlaying = [v(@"triggersWhileAudioPlaying", @NO) boolValue];
    _haptics = [v(@"haptics", @YES) boolValue];
    _recordingHeartbeatInterval = [self.class jwr_normalizedHeartbeatIntervalWithStoredValue:v(@"recordingHeartbeatInterval", @0)];
    _videoStorageMode = [self.class jwr_normalizedVideoStorageModeWithStoredValue:d[@"videoStorageMode"]
                                                        legacySaveVideoToPhotos:[v(@"saveVideoToPhotos", @YES) boolValue]];
    _savePhotoToPhotos = [v(@"savePhotoToPhotos", @YES) boolValue];
    _saveAudioAsVideo = [v(@"saveAudioAsVideo", @NO) boolValue];
    _splitVideoEveryTwoMinutes = [v(@"splitVideoEveryTwoMinutes", @NO) boolValue];
    _videoSegmentDurationSeconds = [self.class jwr_normalizedVideoSegmentDurationWithStoredValue:d[@"videoSegmentDurationSeconds"]
                                                                   legacySplitVideoEveryTwoMinutes:_splitVideoEveryTwoMinutes];
    _embedLocationMetadata = [v(@"embedLocationMetadata", @NO) boolValue];
    _preventWakeWhileRecording = [v(@"preventWakeWhileRecording", @YES) boolValue];
    _cameraPosition = [v(@"cameraPosition", @0) integerValue];
    _zoom = [v(@"zoom", @1.0) doubleValue];
    _fps = [v(@"fps", @30) integerValue];
    _videoQuality = [v(@"videoQuality", @1) integerValue];
    _photoQuality = [v(@"photoQuality", @0.92) doubleValue];
    _filenamePrefix = v(@"filenamePrefix", @"JWR");
    _videoOutputDirectory = [self.class jwr_normalizedVideoOutputDirectoryWithStoredValue:
                             v(@"videoOutputDirectory", @"/var/mobile/Documents/JimWasRecorder")];
    _doubleVolumeUpAction = [v(@"doubleVolumeUpAction", @1) integerValue];
    _doubleVolumeDownAction = [v(@"doubleVolumeDownAction", @2) integerValue];
    _longVolumeUpAction = [v(@"longVolumeUpAction", @0) integerValue];
    _longVolumeDownAction = [v(@"longVolumeDownAction", @0) integerValue];
    _bothVolumesAction = [v(@"bothVolumesAction", @3) integerValue];
    _powerAction = [v(@"powerAction", @0) integerValue];
}
@end
