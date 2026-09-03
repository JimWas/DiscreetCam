#import "JWRPreferences+Normalization.h"
#import "JWRPreferences.h"

static NSString * const JWRDefaultVideoOutputDirectory = @"/var/mobile/Documents/JimWasRecorder";
static NSString * const JWRVideoOutputDirectoryPrefix = @"/var/mobile/";

@implementation JWRPreferences (Normalization)
+ (NSInteger)jwr_normalizedVideoStorageModeWithStoredValue:(id)storedValue legacySaveVideoToPhotos:(BOOL)legacy {
    if (storedValue) return MIN(2, MAX(0, [storedValue integerValue]));
    return legacy ? 2 : 0;
}
+ (NSInteger)jwr_normalizedVideoSegmentDurationWithStoredValue:(id)storedValue legacySplitVideoEveryTwoMinutes:(BOOL)legacy {
    if (storedValue) return MAX(0, [storedValue integerValue]);
    return legacy ? 120 : 0;
}
+ (NSInteger)jwr_normalizedHeartbeatIntervalWithStoredValue:(id)storedValue {
    return MAX(0, [storedValue integerValue]);
}
+ (NSString *)jwr_normalizedVideoOutputDirectoryWithStoredValue:(id)storedValue {
    NSString *standardized = [storedValue isKindOfClass:NSString.class]
        ? [storedValue stringByStandardizingPath] : @"";
    if ([standardized hasPrefix:JWRVideoOutputDirectoryPrefix] &&
        standardized.length > JWRVideoOutputDirectoryPrefix.length) {
        return standardized;
    }
    return JWRDefaultVideoOutputDirectory;
}
@end
