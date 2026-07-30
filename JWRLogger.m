#import "JWRLogger.h"
#import <unistd.h>

void JWRLog(NSString *format, ...) {
    va_list args; va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    NSString *line = [NSString stringWithFormat:@"%@ [%@:%d] %@\n", [formatter stringFromDate:NSDate.date], NSProcessInfo.processInfo.processName, getpid(), message];
    NSLog(@"[JWR] %@", message);
    @try {
        NSString *directory = @"/var/mobile/Documents/JimWasRecorder";
        [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *path = [directory stringByAppendingPathComponent:@"debug.log"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) [@"" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        [handle seekToEndOfFile];
        [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    } @catch (NSException *exception) {
        NSLog(@"[JWR] Logger exception: %@", exception);
    }
}
