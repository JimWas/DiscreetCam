#import <Foundation/Foundation.h>

// Test double replacing JWRMovieValidation (whose real implementation needs
// AVFoundation, unavailable in the GNUstep harness). Keep this header out of
// any translation unit that also imports the production JWRMovieValidation.h
// so the class interface is not declared twice.
@interface JWRMovieValidation : NSObject
+ (void)resetStub;
+ (void)markValid:(NSString *)path;
+ (void)markPlayable:(NSString *)path;
+ (BOOL)validateMovieAtURL:(NSURL *)url reason:(NSString **)reason;
+ (BOOL)isStagedMoviePlayableAtURL:(NSURL *)url;
@end
