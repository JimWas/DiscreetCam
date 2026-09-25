#import <Foundation/Foundation.h>

// Minimal off-device assertion harness for the GNUstep-based JWR tests.
// Compiles with gcc (non-ARC), so avoid ARC-only constructs in test code.

extern int jwrFailures;

#define TAssert(condition) \
    do { \
        if (!(condition)) { \
            jwrFailures++; \
            NSLog(@"FAIL %s:%d: %s", __FILE__, __LINE__, #condition); \
        } \
    } while (0)

// Creates and returns a unique empty directory under NSTemporaryDirectory().
NSString *JWRMakeTempDirectory(void);
void JWRRemoveTempDirectory(NSString *directory);
// Writes `bytes` bytes of zeros to `path`; returns YES on success.
BOOL JWRWriteFile(NSString *path, unsigned long long bytes);
BOOL JWRPathExists(NSString *path);
NSString *JWRJoinPath(NSString *parent, NSString *child);
