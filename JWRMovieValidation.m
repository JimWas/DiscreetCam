#import "JWRMovieValidation.h"
#import <AVFoundation/AVFoundation.h>
#import <math.h>

static const NSTimeInterval JWRMinimumPlayableMovieDuration = 0.10;
static const NSTimeInterval JWRMinimumScannableMovieDuration = 0.05;

@implementation JWRMovieValidation
+ (BOOL)validateMovieAtURL:(NSURL *)url reason:(NSString **)reason {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    NSTimeInterval duration = CMTIME_IS_NUMERIC(asset.duration) ? CMTimeGetSeconds(asset.duration) : 0;
    BOOL hasVideo = [asset tracksWithMediaType:AVMediaTypeVideo].count > 0;
    if (!hasVideo || !isfinite(duration) || duration < JWRMinimumPlayableMovieDuration) {
        if (reason) *reason = [NSString stringWithFormat:@"missing video frames (hasVideo=%d duration=%.3f)", hasVideo, duration];
        return NO;
    }
    return YES;
}
+ (BOOL)isStagedMoviePlayableAtURL:(NSURL *)url {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    return asset.playable && CMTIME_IS_NUMERIC(asset.duration) &&
           CMTimeGetSeconds(asset.duration) > JWRMinimumScannableMovieDuration;
}
@end
