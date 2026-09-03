#import <Foundation/Foundation.h>
#import "JWRTestSupport.h"

void runOutputFilesTests(void);
void runNormalizationTests(void);
void runRouterTests(void);

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int failuresBefore = jwrFailures;

    NSLog(@"suite: JWROutputFiles");
    runOutputFilesTests();
    NSLog(@"suite: JWRPreferences normalization");
    runNormalizationTests();
    NSLog(@"suite: JWRButtonRouter");
    runRouterTests();

    int failures = jwrFailures - failuresBefore;
    if (failures == 0) {
        NSLog(@"JWR tests passed.");
    } else {
        NSLog(@"JWR tests FAILED (%d assertion(s)).", failures);
    }
    [pool drain];
    return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
