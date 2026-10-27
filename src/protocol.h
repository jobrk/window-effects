// Shared wire format: one newline-terminated JSON object per connection.
// Every request carries protocol=1; every response contains an ok success flag.
#pragma once
#import <Foundation/Foundation.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>
#include <math.h>

#define WE_VERSION @"0.1.1"
#define WE_MAX_MESSAGE 65536

static inline NSString *weDirectory(void) {
#ifdef WE_TEST_HOST
    return [NSString stringWithFormat:@"/tmp/window-effects-test-%u", getuid()];
#else
    return [NSString stringWithFormat:@"/tmp/window-effects-%u", getuid()];
#endif
}
static inline NSString *weSocketPath(void) {
    return [weDirectory() stringByAppendingPathComponent:@"control.sock"];
}
// lstat rejects symlinks; the user-owned 0700 directory protects the socket and
// restoration journal from other accounts. Both peers also verify the UID.
static inline bool weDirectoryValid(bool create) {
    const char *path = weDirectory().fileSystemRepresentation;
    if (create && mkdir(path, 0700) && errno != EEXIST)
        return false;
    struct stat st;
    return !lstat(path, &st) && S_ISDIR(st.st_mode) && st.st_uid == getuid() &&
           (st.st_mode & 0777) == 0700;
}
// A dead/stalled peer must not block Dock's serial listener indefinitely.
static inline void weSocketTimeout(int fd) {
    struct timeval timeout = {2, 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
}
static inline bool weSend(int fd, NSDictionary *message) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
    if (!data || data.length >= WE_MAX_MESSAGE)
        return false;
    NSMutableData *line = [data mutableCopy];
    [line appendBytes:"\n" length:1];
    size_t sent = 0;
    while (sent < line.length) {
        ssize_t n = send(fd, (const char *)line.bytes + sent, line.length - sent, 0);
        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0)
            return false;
        sent += (size_t)n;
    }
    return true;
}
static inline NSDictionary *weReceive(int fd) {
    NSMutableData *data = [NSMutableData data];
    char buffer[1024];
    while (data.length < WE_MAX_MESSAGE) {
        ssize_t n = recv(fd, buffer, sizeof(buffer), 0);
        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0)
            return nil;
        char *newline = memchr(buffer, '\n', (size_t)n);
        [data appendBytes:buffer length:newline ? (NSUInteger)(newline - buffer) : (NSUInteger)n];
        if (data.length >= WE_MAX_MESSAGE)
            return nil;
        if (newline) {
            id result = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            return [result isKindOfClass:NSDictionary.class] ? result : nil;
        }
    }
    return nil;
}
// Foundation represents JSON booleans as NSNumber too; reject them as IDs/alpha.
static inline bool weNumber(id value) {
    return [value isKindOfClass:NSNumber.class] &&
           CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID() &&
           isfinite([value doubleValue]);
}
static inline bool weBoolean(id value) {
    return [value isKindOfClass:NSNumber.class] &&
           CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}
static inline NSDictionary *weError(NSString *error) {
    return @{@"ok" : @NO, @"error" : error};
}
static inline NSDictionary *weRequest(NSDictionary *request) {
    if (!weDirectoryValid(false))
        return weError(@"Backend unavailable. Run doctor; load the Dock payload first.");
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0)
        return weError(@"Cannot create socket");
    weSocketTimeout(fd);
    struct sockaddr_un addr = {.sun_family = AF_UNIX};
    strlcpy(addr.sun_path, weSocketPath().fileSystemRepresentation, sizeof(addr.sun_path));
    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr))) {
        close(fd);
        return weError(@"Backend unavailable. Dock may have restarted; reload the payload.");
    }
    uid_t uid;
    gid_t gid;
    if (getpeereid(fd, &uid, &gid) || uid != getuid()) {
        close(fd);
        return weError(@"Backend peer has unexpected owner");
    }
    NSMutableDictionary *message = [request mutableCopy];
    message[@"protocol"] = @1;
    NSDictionary *reply = weSend(fd, message) ? weReceive(fd) : nil;
    close(fd);
    return reply ?: weError(@"Backend communication failed");
}
