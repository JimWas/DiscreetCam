#import <Foundation/Foundation.h>

@interface JWRMovieValidation : NSObject
// AVFoundation-dependent checks only; file-existence and byte-size policy
// live in JWROutputFiles, which decides discard-vs-retain from byte size.
+ (BOOL)validateMovieAtURL:(NSURL *)url reason:(NSString **)reason;
+ (BOOL)isStagedMoviePlayableAtURL:(NSURL *)url;
@end
