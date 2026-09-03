#import <Foundation/Foundation.h>
#import <Block.h>
#import "JWRTestSupport.h"
#import "JWROutputFiles.h"
#import "JWRMovieValidationStub.h"
#import "JWRButtonRouter.h"
#import "JWRPreferences.h"
#import "JWRPreferences+Normalization.h"

// ---------------------------------------------------------------------------
// JWROutputFiles: crash-safe movie staging, finalization, and recovery scan
// ---------------------------------------------------------------------------

static void testOutputURLNaming(void) {
    NSString *root = JWRMakeTempDirectory();
    NSString *videos = JWRJoinPath(root, @"videos");
    NSDate *timestamp = [NSDate dateWithTimeIntervalSinceReferenceDate:1000.5];
    NSURL *url = [JWROutputFiles outputURLWithExtension:@"mov" directory:videos
                                                 prefix:@"JWR" timestamp:timestamp];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd_HH-mm-ss-SSS"];
    NSString *expected = JWRJoinPath(videos, [NSString stringWithFormat:@"JWR_%@.mov",
                                              [formatter stringFromDate:timestamp]]);
    TAssert([url.path isEqualToString:expected]);
    TAssert(JWRPathExists(videos)); // the output directory is created on demand

    NSURL *photoURL = [JWROutputFiles outputURLWithExtension:@"jpg" directory:videos
                                                      prefix:@"CAM" timestamp:timestamp];
    NSString *expectedPhoto = JWRJoinPath(videos, [NSString stringWithFormat:@"CAM_%@.jpg",
                                                   [formatter stringFromDate:timestamp]]);
    TAssert([photoURL.path isEqualToString:expectedPhoto]);
    JWRRemoveTempDirectory(root);
}

static void testFinalURLForStagedURL(void) {
    NSString *root = JWRMakeTempDirectory();
    NSString *videos = JWRJoinPath(root, @"videos");
    NSString *staging = JWRJoinPath(videos, @".inprogress");

    NSURL *staged = [NSURL fileURLWithPath:JWRJoinPath(staging, @"JWR_1.mov")];
    NSURL *final = [JWROutputFiles finalURLForStagedURL:staged recovered:NO];
    TAssert([final.path isEqualToString:JWRJoinPath(videos, @"JWR_1.mov")]);

    NSURL *recovered = [JWROutputFiles finalURLForStagedURL:staged recovered:YES];
    TAssert([recovered.path isEqualToString:JWRJoinPath(videos, @"Recovered_JWR_1.mov")]);
    JWRRemoveTempDirectory(root);
}

static void testFinalizeMovesValidStagedMovie(void) {
    NSString *root = JWRMakeTempDirectory();
    NSString *videos = JWRJoinPath(root, @"videos");
    NSString *staging = JWRJoinPath(videos, @".inprogress");
    [[NSFileManager defaultManager] createDirectoryAtPath:staging
                              withIntermediateDirectories:YES attributes:nil error:NULL];

    NSString *stagedPath = JWRJoinPath(staging, @"JWR_2.mov");
    TAssert(JWRWriteFile(stagedPath, 20000));
    [JWRMovieValidation markValid:stagedPath];

    NSURL *finalURL = nil;
    BOOL moved = [JWROutputFiles finalizeStagedVideoAtURL:[NSURL fileURLWithPath:stagedPath]
                                               recovered:NO finalURL:&finalURL];
    TAssert(moved);
    TAssert(!JWRPathExists(stagedPath));
    TAssert([finalURL.path isEqualToString:JWRJoinPath(videos, @"JWR_2.mov")]);
    TAssert(JWRPathExists(finalURL.path));
    JWRRemoveTempDirectory(root);
}

static void testFinalizeRecoveredPrefixesName(void) {
    NSString *root = JWRMakeTempDirectory();
    NSString *videos = JWRJoinPath(root, @"videos");
    NSString *staging = JWRJoinPath(videos, @".inprogress");
    [[NSFileManager defaultManager] createDirectoryAtPath:staging
                              withIntermediateDirectories:YES attributes:nil error:NULL];

    NSString *stagedPath = JWRJoinPath(staging, @"JWR_3.mov");
    TAssert(JWRWriteFile(stagedPath, 20000));
    [JWRMovieValidation markValid:stagedPath];

    NSURL *finalURL = nil;
    BOOL moved = [JWROutputFiles finalizeStagedVideoAtURL:[NSURL fileURLWithPath:stagedPath]
                                               recovered:YES finalURL:&finalURL];
    TAssert(moved);
    TAssert([finalURL.path isEqualToString:JWRJoinPath(videos, @"Recovered_JWR_3.mov")]);
    TAssert(JWRPathExists(finalURL.path));
    TAssert(!JWRPathExists(stagedPath));
    JWRRemoveTempDirectory(root);
}

static void testFinalizeDiscardsHeaderOnlyMovie(void) {
    NSString *root = JWRMakeTempDirectory();
    NSString *videos = JWRJoinPath(root, @"videos");
    NSString *staging = JWRJoinPath(videos, @".inprogress");
    [[NSFileManager defaultManager] createDirectoryAtPath:staging
                              withIntermediateDirectories:YES attributes:nil error:NULL];

    NSString *stagedPath = JWRJoinPath(staging, @"header_only.mov");
    TAssert(JWRWriteFile(stagedPath, 100)); // far below the 16 KiB floor

    NSURL *sentinel = [NSURL fileURLWithPath:@"sentinel"];
    NSURL *finalURL = sentinel;
    BOOL moved = [JWROutputFiles finalizeStagedVideoAtURL:[NSURL fileURLWithPath:stagedPath]
                                               recovered:NO finalURL:&finalURL];
    TAssert(!moved);
    TAssert(finalURL == sentinel); // untouched on failure
    TAssert(!JWRPathExists(stagedPath)); // header-only files are discarded
    JWRRemoveTempDirectory(root);
}

static void testFinalizeRetainsNontrivialInvalidMovie(void) {
    NSString *root = JWRMakeTempDirectory();
    NSString *videos = JWRJoinPath(root, @"videos");
    NSString *staging = JWRJoinPath(videos, @".inprogress");
    [[NSFileManager defaultManager] createDirectoryAtPath:staging
                              withIntermediateDirectories:YES attributes:nil error:NULL];

    NSString *stagedPath = JWRJoinPath(staging, @"suspicious.mov");
    TAssert(JWRWriteFile(stagedPath, 30000)); // above the byte floor but not playable

    NSURL *finalURL = nil;
    BOOL moved = [JWROutputFiles finalizeStagedVideoAtURL:[NSURL fileURLWithPath:stagedPath]
                                               recovered:NO finalURL:&finalURL];
    TAssert(!moved);
    TAssert(JWRPathExists(stagedPath)); // nontrivial files are kept for manual recovery
    JWRRemoveTempDirectory(root);
}

static void testFinalizeMissingStagedMovieIsNoOp(void) {
    NSString *root = JWRMakeTempDirectory();
    NSString *staging = JWRJoinPath(root, @".inprogress");
    [[NSFileManager defaultManager] createDirectoryAtPath:staging
                              withIntermediateDirectories:YES attributes:nil error:NULL];

    NSURL *missing = [NSURL fileURLWithPath:JWRJoinPath(staging, @"missing.mov")];
    NSURL *sentinel = [NSURL fileURLWithPath:@"sentinel"];
    NSURL *finalURL = sentinel;
    BOOL moved = [JWROutputFiles finalizeStagedVideoAtURL:missing recovered:NO finalURL:&finalURL];
    TAssert(!moved);
    TAssert(finalURL == sentinel);

    BOOL nilMoved = [JWROutputFiles finalizeStagedVideoAtURL:nil recovered:NO finalURL:&finalURL];
    TAssert(!nilMoved);
    JWRRemoveTempDirectory(root);
}

static void testFinalizeRenamesOnCollision(void) {
    NSString *root = JWRMakeTempDirectory();
    NSString *videos = JWRJoinPath(root, @"videos");
    NSString *staging = JWRJoinPath(videos, @".inprogress");
    [[NSFileManager defaultManager] createDirectoryAtPath:staging
                              withIntermediateDirectories:YES attributes:nil error:NULL];

    // A finalized movie with the same name already exists.
    NSString *existingPath = JWRJoinPath(videos, @"JWR_4.mov");
    TAssert(JWRWriteFile(existingPath, 20000));

    NSString *stagedPath = JWRJoinPath(staging, @"JWR_4.mov");
    TAssert(JWRWriteFile(stagedPath, 20000));
    [JWRMovieValidation markValid:stagedPath];

    NSURL *finalURL = nil;
    BOOL moved = [JWROutputFiles finalizeStagedVideoAtURL:[NSURL fileURLWithPath:stagedPath]
                                               recovered:NO finalURL:&finalURL];
    TAssert(moved);
    TAssert(!JWRPathExists(stagedPath));
    TAssert(JWRPathExists(existingPath)); // the pre-existing movie is preserved
    TAssert(![finalURL.path isEqualToString:existingPath]);
    NSString *name = finalURL.lastPathComponent;
    TAssert([name hasPrefix:@"JWR_4_"]);
    TAssert([name hasSuffix:@".mov"]);
    TAssert(JWRPathExists(finalURL.path));
    JWRRemoveTempDirectory(root);
}

static void testRecoveryScanOutcomes(void) {
    NSString *root = JWRMakeTempDirectory();
    NSString *videos = JWRJoinPath(root, @"videos");
    NSString *staging = JWRJoinPath(videos, @".inprogress");
    [[NSFileManager defaultManager] createDirectoryAtPath:staging
                              withIntermediateDirectories:YES attributes:nil error:NULL];

    NSString *playablePath = JWRJoinPath(staging, @"session.mov");
    TAssert(JWRWriteFile(playablePath, 20000));
    [JWRMovieValidation markValid:playablePath];
    [JWRMovieValidation markPlayable:playablePath];

    NSString *headerOnlyPath = JWRJoinPath(staging, @"header_only.mov");
    TAssert(JWRWriteFile(headerOnlyPath, 100));

    NSString *unreadablePath = JWRJoinPath(staging, @"unreadable.mov");
    TAssert(JWRWriteFile(unreadablePath, 30000));

    NSString *unrelatedPath = JWRJoinPath(staging, @"notes.txt");
    TAssert(JWRWriteFile(unrelatedPath, 30000));

    [JWROutputFiles scanAndRecoverStagedVideosInDirectory:staging];

    TAssert(!JWRPathExists(playablePath));
    TAssert(JWRPathExists(JWRJoinPath(videos, @"Recovered_session.mov")));
    TAssert(!JWRPathExists(headerOnlyPath));      // discarded
    TAssert(JWRPathExists(unreadablePath));       // retained for manual recovery
    TAssert(JWRPathExists(unrelatedPath));        // non-movies are ignored

    // A missing directory must not crash the scan.
    [JWROutputFiles scanAndRecoverStagedVideosInDirectory:JWRJoinPath(videos, @"absent")];
    JWRRemoveTempDirectory(root);
}

void runOutputFilesTests(void) {
    testOutputURLNaming();
    testFinalURLForStagedURL();
    testFinalizeMovesValidStagedMovie();
    testFinalizeRecoveredPrefixesName();
    testFinalizeDiscardsHeaderOnlyMovie();
    testFinalizeRetainsNontrivialInvalidMovie();
    testFinalizeMissingStagedMovieIsNoOp();
    testFinalizeRenamesOnCollision();
    testRecoveryScanOutcomes();
}

// ---------------------------------------------------------------------------
// JWRPreferences+Normalization: migration and validation of stored values
// ---------------------------------------------------------------------------

static void testVideoStorageModeNormalization(void) {
    TAssert([JWRPreferences jwr_normalizedVideoStorageModeWithStoredValue:@"3"
                                                   legacySaveVideoToPhotos:YES] == 2); // clamped
    TAssert([JWRPreferences jwr_normalizedVideoStorageModeWithStoredValue:@"-5"
                                                   legacySaveVideoToPhotos:YES] == 0); // clamped
    TAssert([JWRPreferences jwr_normalizedVideoStorageModeWithStoredValue:@"1"
                                                   legacySaveVideoToPhotos:NO] == 1);
    TAssert([JWRPreferences jwr_normalizedVideoStorageModeWithStoredValue:nil
                                                   legacySaveVideoToPhotos:YES] == 2); // migration
    TAssert([JWRPreferences jwr_normalizedVideoStorageModeWithStoredValue:nil
                                                   legacySaveVideoToPhotos:NO] == 0);
}

static void testSegmentDurationNormalization(void) {
    TAssert([JWRPreferences jwr_normalizedVideoSegmentDurationWithStoredValue:@"-10"
                                                  legacySplitVideoEveryTwoMinutes:NO] == 0);
    TAssert([JWRPreferences jwr_normalizedVideoSegmentDurationWithStoredValue:@"300"
                                                  legacySplitVideoEveryTwoMinutes:YES] == 300);
    TAssert([JWRPreferences jwr_normalizedVideoSegmentDurationWithStoredValue:nil
                                                  legacySplitVideoEveryTwoMinutes:YES] == 120); // migration
    TAssert([JWRPreferences jwr_normalizedVideoSegmentDurationWithStoredValue:nil
                                                  legacySplitVideoEveryTwoMinutes:NO] == 0);
}

static void testHeartbeatIntervalNormalization(void) {
    TAssert([JWRPreferences jwr_normalizedHeartbeatIntervalWithStoredValue:@"-1"] == 0);
    TAssert([JWRPreferences jwr_normalizedHeartbeatIntervalWithStoredValue:@"60"] == 60);
    TAssert([JWRPreferences jwr_normalizedHeartbeatIntervalWithStoredValue:@"0"] == 0);
}

static void testVideoOutputDirectoryNormalization(void) {
    NSString *defaultDir = @"/var/mobile/Documents/JimWasRecorder";
    TAssert([[JWRPreferences jwr_normalizedVideoOutputDirectoryWithStoredValue:@"/var/mobile/Videos"]
             isEqualToString:@"/var/mobile/Videos"]);
    TAssert([[JWRPreferences jwr_normalizedVideoOutputDirectoryWithStoredValue:@"/var/mobile"]
             isEqualToString:defaultDir]); // exactly the prefix is rejected
    TAssert([[JWRPreferences jwr_normalizedVideoOutputDirectoryWithStoredValue:@"/var/mobile/"]
             isEqualToString:defaultDir]);
    TAssert([[JWRPreferences jwr_normalizedVideoOutputDirectoryWithStoredValue:@"/etc"]
             isEqualToString:defaultDir]); // outside /var/mobile
    TAssert([[JWRPreferences jwr_normalizedVideoOutputDirectoryWithStoredValue:@"Documents/X"]
             isEqualToString:defaultDir]); // relative paths are rejected
    TAssert([[JWRPreferences jwr_normalizedVideoOutputDirectoryWithStoredValue:@""]
             isEqualToString:defaultDir]);
    TAssert([[JWRPreferences jwr_normalizedVideoOutputDirectoryWithStoredValue:@"/var/mobile/Documents/JimWasRecorder/Sub"]
             isEqualToString:@"/var/mobile/Documents/JimWasRecorder/Sub"]);
}

void runNormalizationTests(void) {
    testVideoStorageModeNormalization();
    testSegmentDurationNormalization();
    testHeartbeatIntervalNormalization();
    testVideoOutputDirectoryNormalization();
}

// ---------------------------------------------------------------------------
// JWRButtonRouter: hardware-trigger gesture state machine and action routing
//
// The GNUstep runtime used by the harness cannot copy blocks, so the router's
// seam blocks are stored by plain assignment and must be created and used
// within one stack frame. The macros below expand in the caller's frame and
// keep the seams alive for the duration of each test. Gesture timing uses the
// router's default monotonic clock with real sleeps; the long-press check is
// deferred through performAfterDelay (a no-op here), so the double-tap
// window, both-buttons chord, action mapping, gating, and routing are
// exercised; the long-press firing path needs a runtime with working block
// copying and is covered on-device.
// ---------------------------------------------------------------------------

#define JWRGestureSetup(router, prefs, actions) \
    router = [JWRButtonRouter new]; \
    router.preferences = (prefs); \
    router.performAfterDelay = ^(NSTimeInterval delay, void (^block)(void)) { (void)delay; (void)block; }; \
    router.runAction = ^(JWRAction action) { [(actions) addObject:@(action)]; }; \
    [router reset]

#define JWRRoutingSetup(router, prefs, posted, locked, foreground) \
    router = [JWRButtonRouter new]; \
    router.preferences = (prefs); \
    router.isDeviceLocked = ^BOOL { return *(locked); }; \
    router.usesForegroundCameraHost = ^BOOL { return *(foreground); }; \
    router.performAfterDelay = ^(NSTimeInterval delay, void (^block)(void)) { (void)delay; (void)block; }; \
    router.postNotification = ^(NSString *name) { [(posted) addObject:name]; }; \
    [router reset]

static void testDoubleTapUpWithinWindow(void) {
    JWRPreferences *prefs = [JWRPreferences new];
    NSMutableArray *actions = [NSMutableArray array];
    JWRButtonRouter *router = nil;
    JWRGestureSetup(router, prefs, actions);

    [router buttonPressedUp];
    [NSThread sleepForTimeInterval:0.2]; // 0.2s < 0.38s window
    [router buttonPressedUp];
    TAssert([actions count] == 1);
    TAssert([[actions objectAtIndex:0] integerValue] == JWRActionVideo); // default doubleUp
}

static void testDoubleTapUpJustOutsideWindow(void) {
    JWRPreferences *prefs = [JWRPreferences new];
    NSMutableArray *actions = [NSMutableArray array];
    JWRButtonRouter *router = nil;
    JWRGestureSetup(router, prefs, actions);

    [router buttonPressedUp];
    [NSThread sleepForTimeInterval:0.5]; // 0.5s >= 0.38s window
    [router buttonPressedUp];
    TAssert([actions count] == 0);
}

static void testBothButtonsChordFiresBothVolumesAction(void) {
    JWRPreferences *prefs = [JWRPreferences new];
    NSMutableArray *actions = [NSMutableArray array];
    JWRButtonRouter *router = nil;
    JWRGestureSetup(router, prefs, actions);

    [router buttonPressedUp];
    [NSThread sleepForTimeInterval:0.05]; // up is still held
    [router buttonPressedDown];
    TAssert([actions count] == 1);
    TAssert([[actions objectAtIndex:0] integerValue] == JWRActionPhoto); // default bothVolumes

    // The complement order works too.
    [router reset];
    [router buttonPressedDown];
    [NSThread sleepForTimeInterval:0.05];
    [router buttonPressedUp];
    TAssert([actions count] == 2);
    TAssert([[actions objectAtIndex:1] integerValue] == JWRActionPhoto);
}

static void testDoubleTapDownFiresConfiguredAction(void) {
    JWRPreferences *prefs = [JWRPreferences new];
    NSMutableArray *actions = [NSMutableArray array];
    JWRButtonRouter *router = nil;
    JWRGestureSetup(router, prefs, actions);

    [router buttonPressedDown];
    [NSThread sleepForTimeInterval:0.2];
    [router buttonPressedDown];
    TAssert([actions count] == 1);
    TAssert([[actions objectAtIndex:0] integerValue] == JWRActionAudio); // default doubleDown
}

static void testConfiguredActionMappingsAreHonored(void) {
    JWRPreferences *prefs = [JWRPreferences new];
    prefs.doubleVolumeUpAction = JWRActionPhoto;
    NSMutableArray *actions = [NSMutableArray array];
    JWRButtonRouter *router = nil;
    JWRGestureSetup(router, prefs, actions);

    [router buttonPressedUp];
    [NSThread sleepForTimeInterval:0.2];
    [router buttonPressedUp];
    TAssert([actions count] == 1);
    TAssert([[actions objectAtIndex:0] integerValue] == JWRActionPhoto);
}

static void testResetClearsGestureState(void) {
    JWRPreferences *prefs = [JWRPreferences new];
    NSMutableArray *actions = [NSMutableArray array];
    JWRButtonRouter *router = nil;
    JWRGestureSetup(router, prefs, actions);

    [router buttonPressedUp];
    [NSThread sleepForTimeInterval:0.3]; // lastUp is now in the past
    [router reset]; // fresh state means no previous press within the window
    [router buttonPressedUp];
    TAssert([actions count] == 0);
}

static void testShouldDeliverActionGates(void) {
    JWRPreferences *prefs = [JWRPreferences new];
    BOOL foreground = NO;
    NSMutableArray *posted = [NSMutableArray array];
    JWRButtonRouter *router = nil;

    // Each phase wires its locked state before creating the seam blocks: the
    // GNU blocks runtime captures block variables by value, so mutating a
    // captured local after wiring would read a stale copy.
    BOOL locked = YES;
    JWRRoutingSetup(router, prefs, posted, &locked, &foreground);

    TAssert(![router shouldDeliverAction:JWRActionNone]); // none is never delivered

    prefs.enabled = NO;
    TAssert(![router shouldDeliverAction:JWRActionVideo]);

    prefs.enabled = YES;
    TAssert(![router shouldDeliverAction:JWRActionVideo]); // locked, triggersWhileLocked off

    prefs.triggersWhileLocked = YES;
    TAssert([router shouldDeliverAction:JWRActionVideo]); // locked but permission granted

    // Unlocked devices deliver regardless of triggersWhileLocked.
    prefs = [JWRPreferences new];
    locked = NO;
    JWRRoutingSetup(router, prefs, posted, &locked, &foreground);
    TAssert([router shouldDeliverAction:JWRActionVideo]);
}

static void testRoutingPostsExpectedNotifications(void) {
    JWRPreferences *prefs = [JWRPreferences new];
    BOOL locked = NO;
    BOOL foreground = NO;
    NSMutableArray *posted = [NSMutableArray array];
    JWRButtonRouter *router = nil;
    JWRRoutingSetup(router, prefs, posted, &locked, &foreground);

    [router routeAction:JWRActionVideo];
    [router routeAction:JWRActionAudio];
    [router routeAction:JWRActionPhoto];
    [router routeAction:JWRActionNone];
    TAssert([posted count] == 3);
    TAssert([[posted objectAtIndex:0] isEqualToString:JWRNotifyVideo]);
    TAssert([[posted objectAtIndex:1] isEqualToString:JWRNotifyAudio]);
    TAssert([[posted objectAtIndex:2] isEqualToString:JWRNotifyPhoto]);
}

static void testDisabledTweakPostsNothing(void) {
    JWRPreferences *prefs = [JWRPreferences new];
    prefs.enabled = NO;
    BOOL locked = NO;
    BOOL foreground = NO;
    NSMutableArray *posted = [NSMutableArray array];
    JWRButtonRouter *router = nil;
    JWRRoutingSetup(router, prefs, posted, &locked, &foreground);

    [router routeAction:JWRActionVideo];
    TAssert([posted count] == 0);
}

static void testLockedDeviceGating(void) {
    JWRPreferences *prefs = [JWRPreferences new];
    BOOL locked = YES;
    BOOL foreground = NO;
    NSMutableArray *posted = [NSMutableArray array];
    JWRButtonRouter *router = nil;
    JWRRoutingSetup(router, prefs, posted, &locked, &foreground);

    [router routeAction:JWRActionAudio];
    TAssert([posted count] == 0); // locked and triggersWhileLocked off

    prefs.triggersWhileLocked = YES;
    [router routeAction:JWRActionAudio];
    TAssert([posted count] == 1);
    TAssert([[posted objectAtIndex:0] isEqualToString:JWRNotifyAudio]);
}

static void testForegroundCameraHostRoutesVideoAndPhotoToLaunchRelay(void) {
    JWRPreferences *prefs = [JWRPreferences new];
    BOOL locked = NO;
    BOOL foreground = YES;
    NSMutableArray *posted = [NSMutableArray array];
    JWRButtonRouter *router = nil;
    JWRRoutingSetup(router, prefs, posted, &locked, &foreground);

    [router routeAction:JWRActionVideo];
    [router routeAction:JWRActionPhoto];
    [router routeAction:JWRActionAudio];
    TAssert([posted count] == 3);
    TAssert([[posted objectAtIndex:0] isEqualToString:JWRNotifyLaunchCameraVideo]);
    TAssert([[posted objectAtIndex:1] isEqualToString:JWRNotifyLaunchCameraPhoto]);
    TAssert([[posted objectAtIndex:2] isEqualToString:JWRNotifyAudio]); // audio unchanged
}

void runRouterTests(void) {
    testDoubleTapUpWithinWindow();
    testDoubleTapUpJustOutsideWindow();
    testBothButtonsChordFiresBothVolumesAction();
    testDoubleTapDownFiresConfiguredAction();
    testConfiguredActionMappingsAreHonored();
    testResetClearsGestureState();
    testShouldDeliverActionGates();
    testRoutingPostsExpectedNotifications();
    testDisabledTweakPostsNothing();
    testLockedDeviceGating();
    testForegroundCameraHostRoutesVideoAndPhotoToLaunchRelay();
}
