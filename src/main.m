#import <Cocoa/Cocoa.h>
#include "protocol.h"
#include <signal.h>
#include <sys/file.h>
#include <poll.h>

static volatile sig_atomic_t stopping;
static volatile sig_atomic_t childPID;
static void stop(int signalNumber) {
    (void)signalNumber;
    stopping = 1;
    if (childPID > 0) kill(childPID, SIGTERM);
}
static void printJSON(NSDictionary *value) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:nil];
    fwrite(data.bytes, 1, data.length, stdout); puts("");
}
static int output(NSDictionary *value) {
    printJSON(value);
    return [value[@"ok"] boolValue] ? 0 : 1;
}
static NSNumber *windowID(NSString *text) {
    if (!text.length || [text rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound)
        return nil;
    unsigned long long n = strtoull(text.UTF8String, NULL, 10);
    return n > 0 && n <= UINT32_MAX ? @((uint32_t)n) : nil;
}
static NSNumber *opacity(NSString *text) {
    const char *start = text.UTF8String; char *end = NULL;
    double n = strtod(start, &end);
    return end != start && !*end && isfinite(n) && n >= 0.1 && n <= 1 ? @(n) : nil;
}
static NSString *aerospacePath(void) {
#ifdef WE_TEST_HOST
    NSString *test = NSProcessInfo.processInfo.environment[@"WE_TEST_AEROSPACE"];
    if (test) return test;
#endif
    // LaunchAgents do not inherit an interactive shell PATH.
    for (NSString *path in @[@"/opt/homebrew/bin/aerospace", @"/usr/local/bin/aerospace"])
        if ([NSFileManager.defaultManager isExecutableFileAtPath:path]) return path;
    for (NSString *dir in [NSProcessInfo.processInfo.environment[@"PATH"] componentsSeparatedByString:@":"]) {
        NSString *path = [dir stringByAppendingPathComponent:@"aerospace"];
        if ([path isAbsolutePath] && [NSFileManager.defaultManager isExecutableFileAtPath:path]) return path;
    }
    return nil;
}
static NSData *runAero(NSArray<NSString *> *arguments) {
    NSString *path = aerospacePath();
    if (!path) return nil;
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:path]; task.arguments = arguments;
    NSPipe *pipe = [NSPipe pipe]; task.standardOutput = pipe;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    if (![task launchAndReturnError:nil]) return nil;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
        dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ if (task.running) [task terminate]; });
    NSData *result = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    return task.terminationStatus == 0 ? result : nil;
}

static void tryAutoload(void) {
#ifndef WE_TEST_HOST
    NSString *loader = @"/Library/Application Support/WindowEffects/loader";
    if (![NSFileManager.defaultManager isExecutableFileAtPath:loader]) return;
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/sudo"];
    // Never prompt from a LaunchAgent. This succeeds only with an existing
    // authorization or the installer’s optional, hash-pinned sudoers entry.
    task.arguments = @[@"-n", @"--", loader];
    task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    if ([task launchAndReturnError:nil]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
            dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ if (task.running) [task terminate]; });
        [task waitUntilExit];
    }
#endif
}
static NSDictionary *configuration(NSString *path) {
    NSMutableDictionary *config = [@{@"activeOpacity": @1.0, @"inactiveOpacity": @0.9,
        @"shadows": @NO, @"excludedApps": @[]} mutableCopy];
    path = path ?: [NSHomeDirectory() stringByAppendingPathComponent:@".config/window-effects/config.json"];
    if ([NSFileManager.defaultManager fileExistsAtPath:path]) {
        NSData *data = [NSData dataWithContentsOfFile:path];
        id value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (![value isKindOfClass:NSDictionary.class]) return nil;
        for (NSString *key in value) if (!config[key]) return nil;
        [config addEntriesFromDictionary:value];
    }
    for (NSString *key in @[@"activeOpacity", @"inactiveOpacity"])
        if (!weNumber(config[key]) || [config[key] doubleValue] < 0.1 || [config[key] doubleValue] > 1) return nil;
    if (!weBoolean(config[@"shadows"]) || ![config[@"excludedApps"] isKindOfClass:NSArray.class]) return nil;
    for (id app in config[@"excludedApps"]) if (![app isKindOfClass:NSString.class]) return nil;
    return config;
}

static NSDictionary *apply(NSDictionary *config) {
    NSData *data = runAero(@[@"list-windows", @"--all", @"--json"]);
    id windows = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![windows isKindOfClass:NSArray.class]) return weError(@"Cannot list AeroSpace windows; is AeroSpace running?");
    NSData *focus = runAero(@[@"list-windows", @"--focused", @"--format", @"%{window-id}"]);
    NSString *text = focus ? [[NSString alloc] initWithData:focus encoding:NSUTF8StringEncoding] : @"";
    NSNumber *focused = windowID([text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]);
    NSArray *cgWindows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID));
    NSMutableDictionary *owners = [NSMutableDictionary dictionary];
    for (NSDictionary *info in cgWindows)
        owners[info[(__bridge NSString *)kCGWindowNumber]] = info[(__bridge NSString *)kCGWindowOwnerPID];
    NSDictionary *status = weRequest(@{@"op": @"status"});
    if (![status[@"ok"] boolValue]) return status;
    NSMutableSet *desired = [NSMutableSet set];
    NSMutableArray *failures = [NSMutableArray array];
    NSUInteger changed = 0;
    for (id info in windows) {
        if (![info isKindOfClass:NSDictionary.class]) return weError(@"Unexpected AeroSpace window format");
        id identifier = info[@"window-id"];
        if (!weNumber(identifier)) return weError(@"Unexpected AeroSpace window ID");
        NSNumber *wid = windowID([identifier stringValue]);
        if (!wid || !owners[wid]) continue;
        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:[owners[wid] intValue]];
        if (!app || app.activationPolicy != NSApplicationActivationPolicyRegular
            || [config[@"excludedApps"] containsObject:app.bundleIdentifier ?: @""]) continue;
        [desired addObject:wid];
        NSDictionary *reply = weRequest(@{@"op": @"set", @"window": wid, @"shadow": config[@"shadows"],
            @"opacity": [wid isEqual:focused] ? config[@"activeOpacity"] : config[@"inactiveOpacity"]});
        if (![reply[@"ok"] boolValue]) [failures addObject:@{@"window": wid, @"result": reply}];
        else if ([reply[@"changed"] boolValue]) changed++;
    }
    for (NSNumber *wid in status[@"windows"]) {
        if (![desired containsObject:wid]) {
            NSDictionary *reply = weRequest(@{@"op": @"restore", @"window": wid});
            if (![reply[@"ok"] boolValue]) [failures addObject:reply];
        }
    }
    return @{@"ok": @(failures.count == 0), @"changed": @(changed), @"failures": failures};
}

static int watch(NSDictionary *config) {
    NSString *path = aerospacePath();
    if (!path) return output(weError(@"AeroSpace CLI not found"));
    if (!weDirectoryValid(true)) return output(weError(@"Invalid runtime directory"));
    NSString *lockPath = [weDirectory() stringByAppendingPathComponent:@"watch.lock"];
    int lock = open(lockPath.fileSystemRepresentation, O_CREAT | O_RDWR | O_NOFOLLOW, 0600);
    if (lock < 0 || flock(lock, LOCK_EX | LOCK_NB)) {
        if (lock >= 0) close(lock);
        return output(weError(@"A watcher is already running, or its lock cannot be opened"));
    }
    signal(SIGTERM, stop); signal(SIGINT, stop); signal(SIGHUP, stop);
    unsigned delay = 1;
    while (!stopping) {
        @autoreleasepool {
            NSDictionary *status = weRequest(@{@"op": @"status"});
            if (![status[@"ok"] boolValue]) {
                tryAutoload();
                fprintf(stderr, "%s\n", [status[@"error"] UTF8String]);
                sleep(delay); delay = MIN(delay * 2, 30); continue;
            }
            NSTask *task = [NSTask new];
            task.executableURL = [NSURL fileURLWithPath:path];
            task.arguments = @[@"subscribe", @"focus-changed", @"window-detected", @"focused-workspace-changed"];
            NSPipe *pipe = [NSPipe pipe]; task.standardOutput = pipe;
            if (![task launchAndReturnError:nil]) { sleep(delay); continue; }
            childPID = task.processIdentifier;
            if (stopping) kill(childPID, SIGTERM);
            NSDictionary *initial = apply(config);
            if (![initial[@"ok"] boolValue]) printJSON(initial);
            FILE *stream = fdopen(dup(pipe.fileHandleForReading.fileDescriptor), "r");
            if (stream) setvbuf(stream, NULL, _IONBF, 0);
            char *line = NULL; size_t size = 0;
            while (!stopping && stream) {
                struct pollfd event = {.fd = fileno(stream), .events = POLLIN};
                int ready = poll(&event, 1, 5000);
                if (ready < 0) { if (errno == EINTR) continue; break; }
                if (!ready) {
                    // Liveness only: no window polling. Dock can restart without
                    // AeroSpace emitting an event, so reconnect the backend here.
                    if (![weRequest(@{@"op": @"status"})[@"ok"] boolValue]) break;
                    continue;
                }
                if (getline(&line, &size, stream) <= 0) break;
                @autoreleasepool {
                    NSDictionary *result = apply(config);
                    if (![result[@"ok"] boolValue]) {
                        printJSON(result);
                        if (![weRequest(@{@"op": @"status"})[@"ok"] boolValue]) break;
                    }
                    delay = 1;
                }
            }
            free(line); if (stream) fclose(stream);
            if (task.running) [task terminate];
            [task waitUntilExit]; childPID = 0;
            // Restore when AeroSpace exits; stale inactive opacity should not linger.
            NSDictionary *restored = weRequest(@{@"op": @"restore"});
            if (![restored[@"ok"] boolValue]) printJSON(restored);
            if (!stopping) { sleep(delay); delay = MIN(delay * 2, 30); }
        }
    }
    close(lock);
    return output(weRequest(@{@"op": @"restore"}));
}

static void usage(void) {
    printf("window-effects %s\n", WE_VERSION.UTF8String);
    puts("Usage: window-effects doctor | --version\n"
         "       window-effects inspect WINDOW_ID\n"
         "       window-effects set WINDOW_ID OPACITY on|off\n"
         "       window-effects restore [WINDOW_ID]\n"
         "       window-effects apply|watch|check-config [CONFIG.json]\n"
         "The last set argument controls shadows. Opacity range: 0.1…1.0.");
}

int main(int argc, char **argv) {
    @autoreleasepool {
        NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
        NSString *command = argc > 1 ? args[1] : @"help";
        if ([command isEqual:@"help"] || [command isEqual:@"--help"]) {
            usage(); return 0;
        }
        if ([command isEqual:@"--version"]) { puts(WE_VERSION.UTF8String); return 0; }
        if ([command isEqual:@"doctor"] && argc == 2) {
            NSDictionary *backend = weRequest(@{@"op": @"status"});
            printJSON(@{@"version": WE_VERSION, @"os": NSProcessInfo.processInfo.operatingSystemVersionString,
                @"aerospace": aerospacePath() ?: (id)NSNull.null, @"backend": backend,
                @"macOS27Tested": @NO});
            return [backend[@"ok"] boolValue] ? 0 : 1;
        }
        if ([command isEqual:@"restore"] && (argc == 2 || argc == 3)) {
            NSNumber *wid = argc == 3 ? windowID(args[2]) : nil;
            if (argc == 3 && !wid) return output(weError(@"Invalid window ID"));
            return output(weRequest(wid ? @{@"op": @"restore", @"window": wid} : @{@"op": @"restore"}));
        }
        if ([command isEqual:@"inspect"] && argc == 3) {
            NSNumber *wid = windowID(args[2]);
            return output(wid ? weRequest(@{@"op": @"inspect", @"window": wid}) : weError(@"Invalid window ID"));
        }
        if ([command isEqual:@"set"] && argc == 5) {
            NSNumber *wid = windowID(args[2]); NSNumber *alpha = opacity(args[3]);
            if (!wid || !alpha || ![@[@"on", @"off"] containsObject:args[4]])
                return output(weError(@"Usage: set WINDOW_ID OPACITY SHADOW(on|off); opacity 0.1…1.0"));
            return output(weRequest(@{@"op": @"set", @"window": wid, @"opacity": alpha,
                @"shadow": @([args[4] isEqual:@"on"])}));
        }
        if ([@[@"apply", @"watch", @"check-config"] containsObject:command] && (argc == 2 || argc == 3)) {
            if (argc == 3 && ![NSFileManager.defaultManager fileExistsAtPath:args[2]])
                return output(weError(@"Configuration file does not exist"));
            NSDictionary *config = configuration(argc == 3 ? args[2] : nil);
            if (!config) return output(weError(@"Invalid configuration: check keys, types and opacity range (0.1…1.0)"));
            if ([command isEqual:@"check-config"]) return output(@{@"ok": @YES, @"config": config});
            return [command isEqual:@"watch"] ? watch(config) : output(apply(config));
        }
        (void)argv;
        usage(); return 2;
    }
}
