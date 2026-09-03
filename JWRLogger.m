#import "JWRLogger.h"
#import <unistd.h>

static const unsigned long long JWRMaxLogFileBytes = 5 * 1024 * 1024;

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
        NSArray<NSString *> *directories = @[
            @"/var/mobile/Library/Logs/JimWasRecorder",
            @"/var/mobile/Documents/JimWasRecorder",
            @"/tmp/JimWasRecorder"
        ];
        NSData *lineData = [line dataUsingEncoding:NSUTF8StringEncoding];
        for (NSString *directory in directories) {
            NSError *directoryError = nil;
            if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
                                            withIntermediateDirectories:YES
                                                             attributes:nil
                                                                  error:&directoryError]) continue;
            NSString *path = [directory stringByAppendingPathComponent:@"debug.log"];
            if (![[NSFileManager defaultManager] fileExistsAtPath:path] &&
                ![[NSData data] writeToFile:path options:NSDataWritingAtomic error:nil]) continue;
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
            if (!handle) continue;
            unsigned long long size = [handle seekToEndOfFile];
            if (size > JWRMaxLogFileBytes) {
                [handle closeFile];
                [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
                if (![[NSData data] writeToFile:path options:NSDataWritingAtomic error:nil]) continue;
                handle = [NSFileHandle fileHandleForWritingAtPath:path];
                if (!handle) continue;
                [handle seekToEndOfFile];
            }
            [handle writeData:lineData];
            [handle closeFile];
            break;
        }
    } @catch (NSException *exception) {
        NSLog(@"[JWR] Logger exception: %@", exception);
    }
}
