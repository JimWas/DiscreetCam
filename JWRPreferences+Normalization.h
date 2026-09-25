#import <Foundation/Foundation.h>

#import "JWRPreferences.h"

@interface JWRPreferences (Normalization)
+ (NSInteger)jwr_normalizedVideoStorageModeWithStoredValue:(id)storedValue legacySaveVideoToPhotos:(BOOL)legacy;
+ (NSInteger)jwr_normalizedVideoSegmentDurationWithStoredValue:(id)storedValue legacySplitVideoEveryTwoMinutes:(BOOL)legacy;
+ (NSInteger)jwr_normalizedHeartbeatIntervalWithStoredValue:(id)storedValue;
+ (NSString *)jwr_normalizedVideoOutputDirectoryWithStoredValue:(id)storedValue;
@end
