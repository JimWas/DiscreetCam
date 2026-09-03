#import <Foundation/Foundation.h>

FOUNDATION_EXPORT const unsigned long long JWRMinimumPlayableMovieBytes;

@interface JWROutputFiles : NSObject
+ (NSURL *)outputURLWithExtension:(NSString *)ext
                        directory:(NSString *)directory
                           prefix:(NSString *)prefix
                        timestamp:(NSDate *)timestamp;
+ (NSURL *)finalURLForStagedURL:(NSURL *)stagedURL recovered:(BOOL)recovered;
+ (BOOL)finalizeStagedVideoAtURL:(NSURL *)stagedURL
                       recovered:(BOOL)recovered
                        finalURL:(NSURL **)finalURL;
+ (void)scanAndRecoverStagedVideosInDirectory:(NSString *)directory;
@end
