#import "JWRTestSupport.h"

int jwrFailures = 0;

NSString *JWRMakeTempDirectory(void) {
    NSString *base = NSTemporaryDirectory();
    NSString *dir = [base stringByAppendingPathComponent:
        [NSString stringWithFormat:@"JWRlogic-%@", NSUUID.UUID.UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return dir;
}

void JWRRemoveTempDirectory(NSString *directory) {
    [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

BOOL JWRWriteFile(NSString *path, unsigned long long bytes) {
    NSMutableData *data = [NSMutableData dataWithCapacity:(NSUInteger)bytes];
    [data setLength:(NSUInteger)bytes];
    return [data writeToFile:path atomically:NO];
}

BOOL JWRPathExists(NSString *path) {
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

NSString *JWRJoinPath(NSString *parent, NSString *child) {
    return [parent stringByAppendingPathComponent:child];
}
