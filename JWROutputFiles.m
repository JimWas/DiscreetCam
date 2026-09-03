#import "JWROutputFiles.h"
#import "JWRMovieValidation.h"
#import "JWRLogger.h"

const unsigned long long JWRMinimumPlayableMovieBytes = 16 * 1024;

@implementation JWROutputFiles
+ (NSURL *)outputURLWithExtension:(NSString *)ext directory:(NSString *)directory prefix:(NSString *)prefix timestamp:(NSDate *)timestamp {
    NSError *directoryError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&directoryError];
    if (directoryError) JWRLog(@"output directory creation failed path=%@ error=%@", directory, directoryError);
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"yyyy-MM-dd_HH-mm-ss-SSS";
    NSString *name = [NSString stringWithFormat:@"%@_%@.%@", prefix, [formatter stringFromDate:timestamp], ext];
    return [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:name]];
}
+ (NSURL *)finalURLForStagedURL:(NSURL *)stagedURL recovered:(BOOL)recovered {
    NSString *name = stagedURL.lastPathComponent;
    if (recovered) name = [@"Recovered_" stringByAppendingString:name];
    NSString *recordingDirectory = stagedURL.URLByDeletingLastPathComponent.URLByDeletingLastPathComponent.path;
    return [NSURL fileURLWithPath:[recordingDirectory stringByAppendingPathComponent:name]];
}
+ (BOOL)finalizeStagedVideoAtURL:(NSURL *)stagedURL recovered:(BOOL)recovered finalURL:(NSURL **)finalURL {
    if (!stagedURL || ![[NSFileManager defaultManager] fileExistsAtPath:stagedURL.path]) return NO;
    unsigned long long bytes = [[[[NSFileManager defaultManager] attributesOfItemAtPath:stagedURL.path error:nil]
                                 objectForKey:NSFileSize] unsignedLongLongValue];
    NSString *validationReason = nil;
    if (![JWRMovieValidation validateMovieAtURL:stagedURL reason:&validationReason]) {
        if (bytes < JWRMinimumPlayableMovieBytes) {
            NSError *removeError = nil;
            [[NSFileManager defaultManager] removeItemAtURL:stagedURL error:&removeError];
            JWRLog(@"discarded header-only staged movie path=%@ bytes=%llu reason=%@ removeError=%@",
                   stagedURL.path, bytes, validationReason, removeError);
        } else {
            JWRLog(@"retained nontrivial invalid staged movie for manual recovery path=%@ bytes=%llu reason=%@",
                   stagedURL.path, bytes, validationReason);
        }
        return NO;
    }
    NSURL *destination = [self finalURLForStagedURL:stagedURL recovered:recovered];
    if ([[NSFileManager defaultManager] fileExistsAtPath:destination.path]) {
        NSString *stem = destination.URLByDeletingPathExtension.lastPathComponent;
        destination = [destination.URLByDeletingLastPathComponent URLByAppendingPathComponent:
                       [NSString stringWithFormat:@"%@_%@.mov", stem, NSUUID.UUID.UUIDString]];
    }
    NSError *moveError = nil;
    BOOL moved = [[NSFileManager defaultManager] moveItemAtURL:stagedURL toURL:destination error:&moveError];
    JWRLog(@"video finalize staged=%@ final=%@ moved=%d error=%@", stagedURL.path, destination.path, moved, moveError);
    if (moved && finalURL) *finalURL = destination;
    return moved;
}
+ (void)scanAndRecoverStagedVideosInDirectory:(NSString *)directory {
    NSArray<NSString *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil];
    for (NSString *name in files) {
        if (![name.pathExtension.lowercaseString isEqualToString:@"mov"]) continue;
        NSURL *url = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:name]];
        BOOL playable = [JWRMovieValidation isStagedMoviePlayableAtURL:url];
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:nil];
        JWRLog(@"recovery scan directory=%@ file=%@ bytes=%@ playable=%d",
               directory, name, [attributes objectForKey:NSFileSize], playable);
        if (playable) {
            NSURL *recoveredURL = nil;
            [self finalizeStagedVideoAtURL:url recovered:YES finalURL:&recoveredURL];
        } else {
            unsigned long long bytes = [[attributes objectForKey:NSFileSize] unsignedLongLongValue];
            if (bytes < JWRMinimumPlayableMovieBytes) {
                NSError *removeError = nil;
                [[NSFileManager defaultManager] removeItemAtURL:url error:&removeError];
                JWRLog(@"removed header-only staged movie path=%@ bytes=%llu error=%@", url.path, bytes, removeError);
            } else {
                JWRLog(@"retained nontrivial staged movie for manual recovery path=%@ bytes=%llu", url.path, bytes);
            }
        }
    }
}
@end
