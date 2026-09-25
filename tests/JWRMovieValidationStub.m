#import "JWRMovieValidationStub.h"

static NSMutableSet *sValidPaths = nil;
static NSMutableSet *sPlayablePaths = nil;

@implementation JWRMovieValidation

+ (void)ensureStorage {
    if (!sValidPaths) {
        sValidPaths = [[NSMutableSet alloc] init];
        sPlayablePaths = [[NSMutableSet alloc] init];
    }
}
+ (void)resetStub {
    [self ensureStorage];
    [sValidPaths removeAllObjects];
    [sPlayablePaths removeAllObjects];
}
+ (void)markValid:(NSString *)path {
    [self ensureStorage];
    [sValidPaths addObject:path];
}
+ (void)markPlayable:(NSString *)path {
    [self ensureStorage];
    [sPlayablePaths addObject:path];
}
+ (BOOL)validateMovieAtURL:(NSURL *)url reason:(NSString **)reason {
    [self ensureStorage];
    if ([sValidPaths containsObject:url.path]) return YES;
    if (reason) *reason = @"stubbed as invalid";
    return NO;
}
+ (BOOL)isStagedMoviePlayableAtURL:(NSURL *)url {
    [self ensureStorage];
    return [sPlayablePaths containsObject:url.path];
}

@end
