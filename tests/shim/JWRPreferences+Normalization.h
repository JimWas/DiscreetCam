// Harness-only shadow of the production JWRPreferences+Normalization.h. The
// production header imports JWRPreferences.h, whose quoted include resolves to
// the production sibling in the repo root; the harness instead needs the shim
// JWRPreferences.h (see shim/JWRPreferences.h). The implementation file
// (JWRPreferences+Normalization.m) is compiled by the harness against the
// production header and is unaffected.
#import <Foundation/Foundation.h>
#import "JWRPreferences.h"

@interface JWRPreferences (Normalization)
+ (NSInteger)jwr_normalizedVideoStorageModeWithStoredValue:(id)storedValue legacySaveVideoToPhotos:(BOOL)legacy;
+ (NSInteger)jwr_normalizedVideoSegmentDurationWithStoredValue:(id)storedValue legacySplitVideoEveryTwoMinutes:(BOOL)legacy;
+ (NSInteger)jwr_normalizedHeartbeatIntervalWithStoredValue:(id)storedValue;
+ (NSString *)jwr_normalizedVideoOutputDirectoryWithStoredValue:(id)storedValue;
@end
