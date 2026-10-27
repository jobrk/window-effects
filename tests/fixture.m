#import <Cocoa/Cocoa.h>
#include "skylight.h"

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:argc == 2 && !strcmp(argv[1], "--regular")
            ? NSApplicationActivationPolicyRegular : NSApplicationActivationPolicyAccessory];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 320, 120)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        window.title = @"Window Effects Test";
        [window orderFront:nil];
        printf("%u\n", (uint32_t)window.windowNumber);
        fflush(stdout);
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:60]];
    }
}
