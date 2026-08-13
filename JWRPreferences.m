#import "JWRPreferences.h"

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
    _recordingHeartbeatInterval = MAX(0, [v(@"recordingHeartbeatInterval", @0) integerValue]);
    id storedVideoStorageMode = d[@"videoStorageMode"];
    _videoStorageMode = storedVideoStorageMode
        ? MIN(2, MAX(0, [storedVideoStorageMode integerValue]))
        : ([v(@"saveVideoToPhotos", @YES) boolValue] ? 2 : 0);
    _savePhotoToPhotos = [v(@"savePhotoToPhotos", @YES) boolValue];
    _saveAudioAsVideo = [v(@"saveAudioAsVideo", @NO) boolValue];
    _splitVideoEveryTwoMinutes = [v(@"splitVideoEveryTwoMinutes", @NO) boolValue];
    id storedSegmentDuration = d[@"videoSegmentDurationSeconds"];
    _videoSegmentDurationSeconds = storedSegmentDuration
        ? MAX(0, [storedSegmentDuration integerValue])
        : (_splitVideoEveryTwoMinutes ? 120 : 0);
    _embedLocationMetadata = [v(@"embedLocationMetadata", @NO) boolValue];
    _preventWakeWhileRecording = [v(@"preventWakeWhileRecording", @YES) boolValue];
    _cameraPosition = [v(@"cameraPosition", @0) integerValue];
    _zoom = [v(@"zoom", @1.0) doubleValue];
    _fps = [v(@"fps", @30) integerValue];
    _videoQuality = [v(@"videoQuality", @1) integerValue];
    _photoQuality = [v(@"photoQuality", @0.92) doubleValue];
    _filenamePrefix = v(@"filenamePrefix", @"JWR");
    NSString *requestedVideoDirectory = v(@"videoOutputDirectory", @"/var/mobile/Documents/JimWasRecorder");
    NSString *standardizedVideoDirectory = [requestedVideoDirectory isKindOfClass:NSString.class]
        ? requestedVideoDirectory.stringByStandardizingPath : @"";
    _videoOutputDirectory =
        [standardizedVideoDirectory hasPrefix:@"/var/mobile/"] && standardizedVideoDirectory.length > @"/var/mobile/".length
            ? standardizedVideoDirectory
            : @"/var/mobile/Documents/JimWasRecorder";
    _doubleVolumeUpAction = [v(@"doubleVolumeUpAction", @1) integerValue];
    _doubleVolumeDownAction = [v(@"doubleVolumeDownAction", @2) integerValue];
    _longVolumeUpAction = [v(@"longVolumeUpAction", @0) integerValue];
    _longVolumeDownAction = [v(@"longVolumeDownAction", @0) integerValue];
    _bothVolumesAction = [v(@"bothVolumesAction", @3) integerValue];
    _powerAction = [v(@"powerAction", @0) integerValue];
}
@end
