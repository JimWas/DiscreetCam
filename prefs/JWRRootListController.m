#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <AVFoundation/AVFoundation.h>
#import <notify.h>
#import "../JWRConstants.h"
#import "../JWRLogger.h"

@interface JWRRootListController : PSListController @end
@implementation JWRRootListController
- (NSString *)actionName:(NSInteger)value {
    NSArray *names = @[@"None", @"Video", @"Audio", @"Photo"];
    return value >= 0 && value < (NSInteger)names.count ? names[value] : @"None";
}
- (NSInteger)currentSegmentDuration {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:JWRPrefsID];
    id storedDuration = [defaults objectForKey:@"videoSegmentDurationSeconds"];
    if (storedDuration) return MAX(0, [storedDuration integerValue]);
    return [defaults boolForKey:@"splitVideoEveryTwoMinutes"] ? 120 : 0;
}
- (NSString *)segmentDurationTitle:(NSInteger)seconds {
    if (seconds <= 0) return @"Off";
    if (seconds < 60) return [NSString stringWithFormat:@"%ld sec", (long)seconds];
    NSInteger minutes = seconds / 60;
    NSInteger remainder = seconds % 60;
    if (remainder == 0) return [NSString stringWithFormat:@"%ld min", (long)minutes];
    return [NSString stringWithFormat:@"%ld min %ld sec", (long)minutes, (long)remainder];
}
- (NSString *)currentVideoOutputDirectory {
    NSString *fallback = @"/var/mobile/Documents/JimWasRecorder";
    id stored = [[[NSUserDefaults alloc] initWithSuiteName:JWRPrefsID] objectForKey:@"videoOutputDirectory"];
    if (![stored isKindOfClass:NSString.class]) return fallback;
    NSString *path = [stored stringByStandardizingPath];
    return [path hasPrefix:@"/var/mobile/"] && path.length > @"/var/mobile/".length ? path : fallback;
}
- (NSString *)videoDirectoryTitle:(NSString *)path {
    NSString *name = path.lastPathComponent;
    return name.length ? name : path;
}
- (void)showVideoDirectoryError:(NSString *)message {
    UIAlertController *error =
        [UIAlertController alertControllerWithTitle:@"Invalid Video Folder"
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    [error addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:error animated:YES completion:nil];
}
- (NSArray *)specifiers {
    JWRLog(@"Settings requested specifiers bundle=%@", [NSBundle bundleForClass:self.class].bundlePath);
    if (!_specifiers) {
        NSString *path = [[NSBundle bundleForClass:self.class] pathForResource:@"Root" ofType:@"plist"];
        NSArray *definitions = [NSArray arrayWithContentsOfFile:path];
        NSMutableArray *built = [NSMutableArray array];
        NSDictionary *cells = @{@"PSGroupCell":@(PSGroupCell), @"PSLinkCell":@(PSLinkCell), @"PSLinkListCell":@(PSLinkListCell), @"PSListItemCell":@(PSListItemCell), @"PSTitleValueCell":@(PSTitleValueCell), @"PSSliderCell":@(PSSliderCell), @"PSSwitchCell":@(PSSwitchCell), @"PSStaticTextCell":@(PSStaticTextCell), @"PSEditTextCell":@(PSEditTextCell), @"PSSegmentCell":@(PSSegmentCell), @"PSButtonCell":@(PSButtonCell)};
        NSSet *pickerKeys = [NSSet setWithArray:@[@"cameraPosition", @"zoom", @"fps", @"videoQuality", @"recordingHeartbeatInterval", @"doubleVolumeUpAction", @"doubleVolumeDownAction", @"bothVolumesAction"]];
        NSInteger selectedPosition = [[[NSUserDefaults alloc] initWithSuiteName:JWRPrefsID] integerForKey:@"cameraPosition"];
        AVCaptureDevicePosition position = selectedPosition == 1 ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
        BOOL hasWide = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:position] != nil;
        BOOL hasUltraWide = position == AVCaptureDevicePositionBack &&
            [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInUltraWideCamera mediaType:AVMediaTypeVideo position:position] != nil;
        for (NSDictionary *originalDefinition in definitions) {
            NSMutableDictionary *definition = [originalDefinition mutableCopy];
            if ([definition[@"key"] isEqualToString:@"zoom"]) {
                NSMutableArray *titles = [NSMutableArray array];
                NSMutableArray *values = [NSMutableArray array];
                if (hasUltraWide) { [titles addObject:@"0.5×"]; [values addObject:@0.5]; }
                if (hasWide) { [titles addObject:@"1×"]; [values addObject:@1.0]; }
                if (titles.count <= 1) {
                    JWRLog(@"hiding lens picker; selected camera has only one supported lens");
                    continue;
                }
                definition[@"validTitles"] = titles;
                definition[@"validValues"] = values;
            }
            PSCellType type = [cells[definition[@"cell"]] integerValue];
            BOOL isPicker = [pickerKeys containsObject:definition[@"key"]];
            BOOL isSegmentDuration = [definition[@"key"] isEqualToString:@"videoSegmentDurationSeconds"];
            BOOL isVideoDirectory = [definition[@"key"] isEqualToString:@"videoOutputDirectory"];
            if (isPicker || isSegmentDuration || isVideoDirectory) type = PSButtonCell;
            Class detail = type == PSLinkListCell ? NSClassFromString(@"PSListItemsController") : Nil;
            SEL setter = type == PSGroupCell ? NULL : @selector(setPreferenceValue:specifier:);
            SEL getter = type == PSGroupCell ? NULL : @selector(readPreferenceValue:);
            PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:definition[@"label"] target:self set:setter get:getter detail:detail cell:type edit:Nil];
            for (NSString *key in definition)
                if (![key isEqualToString:@"cell"] && ![key isEqualToString:@"label"]) [specifier setProperty:definition[key] forKey:key];
            if (isPicker) {
                id currentValue = [self readPreferenceValue:specifier];
                NSArray *values = definition[@"validValues"];
                NSArray *titles = definition[@"validTitles"];
                NSUInteger index = [values indexOfObject:currentValue];
                NSString *currentTitle = index != NSNotFound && index < titles.count ? titles[index] : @"Choose";
                specifier.name = [NSString stringWithFormat:@"%@: %@", definition[@"label"], currentTitle];
                specifier.buttonAction = @selector(selectPickerOption:);
            } else if (isSegmentDuration) {
                specifier.name = [NSString stringWithFormat:@"%@: %@", definition[@"label"],
                                  [self segmentDurationTitle:[self currentSegmentDuration]]];
                specifier.buttonAction = @selector(selectSegmentDuration:);
            } else if (isVideoDirectory) {
                NSString *path = [self currentVideoOutputDirectory];
                specifier.name = [NSString stringWithFormat:@"%@: %@", definition[@"label"],
                                  [self videoDirectoryTitle:path]];
                specifier.buttonAction = @selector(selectVideoOutputDirectory:);
            }
            [built addObject:specifier];
        }
        _specifiers = built;
        JWRLog(@"Settings source path=%@ definitions=%lu", path, (unsigned long)definitions.count);
    }
    JWRLog(@"Settings loaded %lu specifiers", (unsigned long)_specifiers.count);
    return _specifiers;
}
- (void)selectPickerOption:(PSSpecifier *)specifier {
    NSArray *titles = [specifier propertyForKey:@"validTitles"];
    NSArray *values = [specifier propertyForKey:@"validValues"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:specifier.name message:@"Choose an option." preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSUInteger index = 0; index < titles.count && index < values.count; index++) {
        [alert addAction:[UIAlertAction actionWithTitle:titles[index] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self setPreferenceValue:values[index] specifier:specifier];
            NSString *base = [[specifier.name componentsSeparatedByString:@":"] firstObject];
            specifier.name = [NSString stringWithFormat:@"%@: %@", base, titles[index]];
            [self reloadSpecifier:specifier];
            if ([[specifier propertyForKey:@"key"] isEqualToString:@"cameraPosition"]) {
                _specifiers = nil;
                [self reloadSpecifiers];
            }
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)selectVideoOutputDirectory:(PSSpecifier *)specifier {
    NSString *defaultPath = @"/var/mobile/Documents/JimWasRecorder";
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Video Save Folder"
                                            message:@"Enter an absolute writable folder under /var/mobile. The folder will be created if it does not exist."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = [self currentVideoOutputDirectory];
        textField.placeholder = defaultPath;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    __weak typeof(self) weakSelf = self;
    void (^savePath)(NSString *) = ^(NSString *requestedPath) {
        typeof(self) self = weakSelf;
        if (!self) return;
        NSString *trimmed = [requestedPath stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *path = trimmed.stringByStandardizingPath;
        if (![trimmed hasPrefix:@"/"] || ![path hasPrefix:@"/var/mobile/"] || path.length <= @"/var/mobile/".length) {
            JWRLog(@"rejected invalid video output directory=%@", requestedPath);
            [self showVideoDirectoryError:@"Choose an absolute path inside /var/mobile, such as /var/mobile/Documents/My Videos."];
            return;
        }
        NSError *directoryError = nil;
        BOOL created = [[NSFileManager defaultManager] createDirectoryAtPath:path
                                                 withIntermediateDirectories:YES
                                                                  attributes:nil
                                                                       error:&directoryError];
        BOOL isDirectory = NO;
        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory];
        BOOL writable = [[NSFileManager defaultManager] isWritableFileAtPath:path];
        if (!created || directoryError || !exists || !isDirectory || !writable) {
            JWRLog(@"video output directory unavailable path=%@ created=%d exists=%d directory=%d writable=%d error=%@",
                   path, created, exists, isDirectory, writable, directoryError);
            [self showVideoDirectoryError:@"That folder could not be created or is not writable by the mobile user. Choose another folder under /var/mobile."];
            return;
        }
        [self setPreferenceValue:path specifier:specifier];
        specifier.name = [NSString stringWithFormat:@"Video Save Folder: %@", [self videoDirectoryTitle:path]];
        [self reloadSpecifier:specifier];
        JWRLog(@"video output directory changed to %@", path);
    };
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        savePath(alert.textFields.firstObject.text);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Use Default" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        savePath(defaultPath);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)selectSegmentDuration:(PSSpecifier *)specifier {
    NSInteger currentDuration = [self currentSegmentDuration];
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Video Segment Length"
                                            message:@"Enter the duration of each video file in seconds (10–86400). Enter 0 to record one continuous file."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.keyboardType = UIKeyboardTypeNumberPad;
        textField.placeholder = @"Example: 120";
        textField.text = [NSString stringWithFormat:@"%ld", (long)currentDuration];
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        typeof(self) self = weakSelf;
        if (!self) return;
        NSString *input = [alert.textFields.firstObject.text
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSCharacterSet *nonDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet;
        BOOL digitsOnly = input.length > 0 && [input rangeOfCharacterFromSet:nonDigits].location == NSNotFound;
        NSInteger seconds = digitsOnly ? input.integerValue : -1;
        if (!digitsOnly || (seconds != 0 && (seconds < 10 || seconds > 86400))) {
            JWRLog(@"rejected invalid video segment duration input=%@", input);
            UIAlertController *error =
                [UIAlertController alertControllerWithTitle:@"Invalid Duration"
                                                    message:@"Use 0 to disable segmentation, or enter a whole number from 10 through 86400 seconds."
                                             preferredStyle:UIAlertControllerStyleAlert];
            [error addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:error animated:YES completion:nil];
            return;
        }
        [self setPreferenceValue:@(seconds) specifier:specifier];
        specifier.name = [NSString stringWithFormat:@"Video Segment Length: %@",
                          [self segmentDurationTitle:seconds]];
        [self reloadSpecifier:specifier];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    JWRLog(@"setting changed key=%@ value=%@", [specifier propertyForKey:@"key"], value);
    [super setPreferenceValue:value specifier:specifier];
    CFPreferencesAppSynchronize((__bridge CFStringRef)JWRPrefsID);
    notify_post(JWRNotifyReload.UTF8String);
}
@end
