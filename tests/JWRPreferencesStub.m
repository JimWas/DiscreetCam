#import "JWRPreferences.h"

// Test double for JWRPreferences: the production loader reads the live
// CFPreferences domain via -reload, which must not run in the harness. This
// implementation keeps a fresh instance that starts with the same defaults
// the production loader would apply for an empty domain.
@implementation JWRPreferences

@synthesize enabled;
@synthesize triggersWhileLocked;
@synthesize triggersWhileAudioPlaying;
@synthesize haptics;
@synthesize recordingHeartbeatInterval;
@synthesize videoStorageMode;
@synthesize savePhotoToPhotos;
@synthesize saveAudioAsVideo;
@synthesize splitVideoEveryTwoMinutes;
@synthesize videoSegmentDurationSeconds;
@synthesize embedLocationMetadata;
@synthesize preventWakeWhileRecording;
@synthesize cameraPosition;
@synthesize zoom;
@synthesize fps;
@synthesize videoQuality;
@synthesize photoQuality;
@synthesize filenamePrefix;
@synthesize videoOutputDirectory;
@synthesize doubleVolumeUpAction;
@synthesize doubleVolumeDownAction;
@synthesize longVolumeUpAction;
@synthesize longVolumeDownAction;
@synthesize bothVolumesAction;
@synthesize powerAction;

+ (instancetype)shared {
    static JWRPreferences *sharedInstance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sharedInstance = [[JWRPreferences alloc] init]; });
    return sharedInstance;
}

- (instancetype)init {
    if ((self = [super init])) {
        enabled = YES;
        triggersWhileLocked = NO;
        haptics = YES;
        savePhotoToPhotos = YES;
        preventWakeWhileRecording = YES;
        zoom = 1.0;
        fps = 30;
        videoQuality = 1;
        photoQuality = 0.92;
        filenamePrefix = @"JWR";
        videoOutputDirectory = @"/var/mobile/Documents/JimWasRecorder";
        doubleVolumeUpAction = JWRActionVideo;
        doubleVolumeDownAction = JWRActionAudio;
        longVolumeUpAction = JWRActionNone;
        longVolumeDownAction = JWRActionNone;
        bothVolumesAction = JWRActionPhoto;
        powerAction = JWRActionNone;
    }
    return self;
}

- (void)reload {
    // No-op: loading the real preference domain would touch the host machine.
}
@end
