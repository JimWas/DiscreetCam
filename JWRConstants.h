#import <Foundation/Foundation.h>

static NSString * const JWRPrefsID = @"com.jimwas.recorder";
static NSString * const JWRNotifyVideo = @"com.jimwas.recorder/toggleVideo";
static NSString * const JWRNotifyAudio = @"com.jimwas.recorder/toggleAudio";
static NSString * const JWRNotifyPhoto = @"com.jimwas.recorder/takePhoto";
static NSString * const JWRNotifyForegroundVideo = @"com.jimwas.recorder/foregroundVideo";
static NSString * const JWRNotifyForegroundPhoto = @"com.jimwas.recorder/foregroundPhoto";
static NSString * const JWRNotifyLaunchCameraVideo = @"com.jimwas.recorder/launchCameraVideo";
static NSString * const JWRNotifyLaunchCameraPhoto = @"com.jimwas.recorder/launchCameraPhoto";
static NSString * const JWRNotifyTriggerVideo = @"com.jimwas.recorder/triggerVideo";
static NSString * const JWRNotifyTriggerAudio = @"com.jimwas.recorder/triggerAudio";
static NSString * const JWRNotifyReload = @"com.jimwas.recorder/reload";
static NSString * const JWRNotifyState = @"com.jimwas.recorder/stateChanged";
static NSString * const JWRNotifyHapticStarted = @"com.jimwas.recorder/hapticStarted";
static NSString * const JWRNotifyHapticStopped = @"com.jimwas.recorder/hapticStopped";
static NSString * const JWRNotifyHapticPhoto = @"com.jimwas.recorder/hapticPhoto";
static NSString * const JWRNotifyHapticHeartbeat = @"com.jimwas.recorder/hapticHeartbeat";
static NSString * const JWRNotifyHapticFailure = @"com.jimwas.recorder/hapticFailure";
static NSString * const JWRNotifyHapticVideoStarted = @"com.jimwas.recorder/hapticVideoStarted";
static NSString * const JWRNotifyHapticVideoStopped = @"com.jimwas.recorder/hapticVideoStopped";

typedef NS_ENUM(NSInteger, JWRAction) {
    JWRActionNone = 0,
    JWRActionVideo = 1,
    JWRActionAudio = 2,
    JWRActionPhoto = 3
};

// JWRNotifyState payload bits. SpringBoard owns video state and the launch
// service owns audio state; each process publishes only its own bit so the
// shared value preserves the other side's state.
static const uint64_t JWRStateVideoActive = 1ull << 0;
static const uint64_t JWRStateAudioActive = 1ull << 1;
