#pragma once
#import <Cocoa/Cocoa.h>
#include <dlfcn.h>
#include <math.h>

// Private APIs, isolated here. A successful lookup is not a compatibility test.
typedef struct {
    int (*connection)(void);
    CGError (*getAlpha)(int, uint32_t, float *);
    CGError (*setAlpha)(int, uint32_t, float);
    CGError (*getTags)(int, uint32_t, uint64_t *, int);
    CGError (*setTags)(int, uint32_t, uint64_t *, int);
    CGError (*clearTags)(int, uint32_t, uint64_t *, int);
    CGError (*getOwner)(int, uint32_t, int *);
} WEAPI;

static inline bool weLoad(WEAPI *api) {
    void *lib = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW);
    if (!lib)
        return false;
#define LOAD(field, symbol)                                                                        \
    *(void **)(&api->field) = dlsym(lib, symbol);                                                  \
    if (!api->field)                                                                               \
    return false
    LOAD(connection, "SLSMainConnectionID");
    LOAD(getAlpha, "SLSGetWindowAlpha");
    LOAD(setAlpha, "SLSSetWindowAlpha");
    LOAD(getTags, "SLSGetWindowTags");
    LOAD(setTags, "SLSSetWindowTags");
    LOAD(clearTags, "SLSClearWindowTags");
    LOAD(getOwner, "SLSGetWindowOwner");
#undef LOAD
    return true;
}

static inline CGError weShadow(WEAPI api, uint32_t wid, bool enabled) {
    // Bit 3 suppresses the WindowServer shadow: enabling shadows clears it.
    // AppKit titlebar rims and application-drawn CSS are separate decorations.
    uint64_t tags = UINT64_C(1) << 3;
    return enabled ? api.clearTags(api.connection(), wid, &tags, 64)
                   : api.setTags(api.connection(), wid, &tags, 64);
}
