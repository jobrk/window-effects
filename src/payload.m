// Runs inside Dock. This serial service owns restoration state and performs
// verified appearance changes; layout, shortcuts and app selection stay outside.
#include "skylight.h"
#include "protocol.h"

static WEAPI api;
// Window IDs can be reused. Each snapshot also records the WindowServer
// connection that owned it, so restoration cannot target a replacement window.
static NSMutableDictionary<NSNumber *, NSDictionary *> *originals;

// Atomic replacement keeps a failed write from truncating the existing journal.
static bool saveOriginals(void) {
    NSMutableDictionary *json = [NSMutableDictionary dictionary];
    for (NSNumber *wid in originals)
        json[wid.stringValue] = originals[wid];
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
    return data &&
           [data writeToFile:[weDirectory() stringByAppendingPathComponent:@"originals.json"]
                     options:NSDataWritingAtomic
                       error:nil];
}

static NSDictionary *readWindow(uint32_t wid) {
    float alpha = 0;
    uint64_t tags = 0;
    int owner = 0;
    if (api.getAlpha(api.connection(), wid, &alpha) ||
        api.getTags(api.connection(), wid, &tags, 64) ||
        api.getOwner(api.connection(), wid, &owner))
        return nil;
    return @{
        @"opacity" : @(alpha),
        @"shadow" : @((BOOL) !(tags & (UINT64_C(1) << 3))),
        @"owner" : @(owner)
    };
}

// Never mutate system surfaces, panels on other layers, or Dock's own windows.
static bool ordinaryWindow(uint32_t wid) {
    NSArray *list =
        CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionIncludingWindow, wid));
    if (list.count != 1)
        return false;
    NSDictionary *info = list.firstObject;
    if ([info[(__bridge NSString *)kCGWindowLayer] intValue] != 0)
        return false;
    pid_t pid = [info[(__bridge NSString *)kCGWindowOwnerPID] intValue];
#ifdef WE_TEST_HOST
    return pid == getpid(); // Tests may change only their own disposable windows.
#else
    if (pid <= 0 || pid == getpid())
        return false;
    NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    return app && app.activationPolicy == NSApplicationActivationPolicyRegular;
#endif
}

static bool equalAppearance(NSDictionary *a, NSDictionary *b) {
    return a && b && fabs([a[@"opacity"] doubleValue] - [b[@"opacity"] doubleValue]) < 0.005 &&
           [a[@"shadow"] boolValue] == [b[@"shadow"] boolValue];
}

static bool writeWindow(uint32_t wid, NSDictionary *appearance) {
    CGError a = api.setAlpha(api.connection(), wid, [appearance[@"opacity"] floatValue]);
    CGError s = weShadow(api, wid, [appearance[@"shadow"] boolValue]);
    // The OS can silently ignore private setters, even when they return success.
    return !a && !s && equalAppearance(readWindow(wid), appearance);
}

static void pruneClosed(void) {
    // SkyLight can return stale alpha/tags/owner data after a window closes.
    // Check the public WindowServer list before trusting those private getters.
    NSArray *windows =
        CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID));
    if (!windows)
        return; // Keep restoration state if enumeration itself fails.
    NSMutableSet *live = [NSMutableSet set];
    for (NSDictionary *window in windows)
        [live addObject:window[(__bridge NSString *)kCGWindowNumber]];
    for (NSNumber *wid in originals.allKeys) {
        NSDictionary *current = readWindow(wid.unsignedIntValue);
        if (![live containsObject:wid] || !current ||
            ![current[@"owner"] isEqual:originals[wid][@"owner"]])
            [originals removeObjectForKey:wid];
    }
}

static NSDictionary *restore(NSNumber *only) {
    pruneClosed();
    NSMutableArray *failed = [NSMutableArray array];
    NSUInteger restored = 0;
    for (NSNumber *wid in only ? @[ only ] : originals.allKeys) {
        NSDictionary *original = originals[wid];
        if (!original)
            continue;
        if (writeWindow(wid.unsignedIntValue, original)) {
            [originals removeObjectForKey:wid];
            restored++;
        } else
            [failed addObject:wid];
    }
    bool saved = saveOriginals();
    return @{
        @"ok" : @(failed.count == 0 && saved),
        @"restored" : @(restored),
        @"failed" : failed,
        @"journalSaved" : @(saved)
    };
}

static NSDictionary *handle(NSDictionary *request) {
    if (!weNumber(request[@"protocol"]) || [request[@"protocol"] doubleValue] != 1)
        return weError(@"Unsupported protocol");
    NSString *op = request[@"op"];
    if (![op isKindOfClass:NSString.class])
        return weError(@"Missing operation");
    if ([op isEqual:@"status"]) {
        pruneClosed();
        return @{
            @"ok" : @YES,
            @"version" : WE_VERSION,
            @"pid" : @(getpid()),
            @"savedWindows" : @(originals.count),
            @"windows" : originals.allKeys,
            @"os" : NSProcessInfo.processInfo.operatingSystemVersionString
        };
    }
    NSNumber *wid = request[@"window"];
    if ([op isEqual:@"restore"] && !wid)
        return restore(nil);
    if (!weNumber(wid) || wid.doubleValue < 1 || wid.doubleValue > UINT32_MAX ||
        floor(wid.doubleValue) != wid.doubleValue)
        return weError(@"Invalid window ID");
    if ([op isEqual:@"restore"])
        return restore(wid);
    NSDictionary *before = readWindow(wid.unsignedIntValue);
    if (!before)
        return weError(@"Window disappeared or cannot be inspected");
    if ([op isEqual:@"inspect"])
        return @{@"ok" : @YES, @"window" : wid, @"appearance" : before};
    if (![op isEqual:@"set"])
        return weError(@"Unknown operation");
    NSNumber *alpha = request[@"opacity"];
    id shadow = request[@"shadow"];
    if (!weNumber(alpha) || alpha.doubleValue < 0.1 || alpha.doubleValue > 1.0 ||
        !weBoolean(shadow))
        return weError(@"opacity must be 0.1…1.0; shadow must be boolean");
    if (!ordinaryWindow(wid.unsignedIntValue))
        return weError(@"Only ordinary application windows can be changed");
    pruneClosed();
    NSDictionary *desired = @{@"opacity" : alpha, @"shadow" : shadow};
    if (equalAppearance(before, desired))
        return @{@"ok" : @YES, @"changed" : @NO};
    // Persist the first observed state before any change. Repeated focus updates
    // must not overwrite the snapshot with our own previous effects.
    if (!originals[wid]) {
        originals[wid] = before;
        if (!saveOriginals()) {
            [originals removeObjectForKey:wid];
            return weError(@"Cannot save restoration journal; window unchanged");
        }
    }
    // A setter can partially succeed. Try to undo this request, but retain the
    // original snapshot even if rollback fails so restore can be retried.
    if (!writeWindow(wid.unsignedIntValue, desired)) {
        NSDictionary *observed = readWindow(wid.unsignedIntValue);
        bool rolledBack = writeWindow(wid.unsignedIntValue, before);
        return @{
            @"ok" : @NO,
            @"error" : @"Private API change was rejected or failed readback verification",
            @"observed" : observed ?: @{},
            @"rolledBack" : @(rolledBack)
        };
    }
    return @{@"ok" : @YES, @"changed" : @YES};
}

static void serve(void) {
    @autoreleasepool {
        if (!weLoad(&api) || !weDirectoryValid(true))
            return;
        NSString *path = weSocketPath();
        struct stat st;
        if (!lstat(path.fileSystemRepresentation, &st)) {
            if (!S_ISSOCK(st.st_mode) || st.st_uid != getuid())
                return;
            // A previous instance may be live; never steal its endpoint/state.
            if ([weRequest(@{@"op" : @"status"})[@"ok"] boolValue])
                return;
            if (unlink(path.fileSystemRepresentation))
                return;
        }
        int server = socket(AF_UNIX, SOCK_STREAM, 0);
        if (server < 0)
            return;
        struct sockaddr_un addr = {.sun_family = AF_UNIX};
        strlcpy(addr.sun_path, path.fileSystemRepresentation, sizeof(addr.sun_path));
        if (bind(server, (struct sockaddr *)&addr, sizeof(addr)) ||
            chmod(path.fileSystemRepresentation, 0600) || listen(server, 8)) {
            close(server);
            return;
        }
        originals = [NSMutableDictionary dictionary];
        NSData *saved =
            [NSData dataWithContentsOfFile:[weDirectory()
                                               stringByAppendingPathComponent:@"originals.json"]];
        id json = saved ? [NSJSONSerialization JSONObjectWithData:saved options:0 error:nil] : nil;
        if ([json isKindOfClass:NSDictionary.class]) {
            for (NSString *key in json) {
                id value = json[key];
                if ([value isKindOfClass:NSDictionary.class] && weNumber(value[@"opacity"]) &&
                    [value[@"opacity"] doubleValue] >= 0 && [value[@"opacity"] doubleValue] <= 1 &&
                    weBoolean(value[@"shadow"]) && weNumber(value[@"owner"])) {
                    unsigned long long n = strtoull(key.UTF8String, NULL, 10);
                    if (n > 0 && n <= UINT32_MAX)
                        originals[@((uint32_t)n)] = value;
                }
            }
        }
        pruneClosed();
        // One request per connection, served serially: no two clients can race
        // journal updates. Socket timeouts bound a stalled client's occupancy.
        for (;;) {
            @autoreleasepool {
                int fd = accept(server, NULL, NULL);
                if (fd < 0) {
                    if (errno == EINTR)
                        continue;
                    break;
                }
                weSocketTimeout(fd);
                uid_t uid;
                gid_t gid;
                if (!getpeereid(fd, &uid, &gid) && uid == getuid()) {
                    NSDictionary *request = weReceive(fd);
                    if (request)
                        weSend(fd, handle(request));
                }
                close(fd);
            }
        }
        close(server);
    }
}

__attribute__((constructor)) static void start(void) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        serve();
    });
}
