#import <Cocoa/Cocoa.h>
#include "skylight.h"

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:argc == 2 && !strcmp(argv[1], "--regular")
            ? NSApplicationActivationPolicyRegular : NSApplicationActivationPolicyAccessory];
        [NSApp finishLaunching];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 320, 120)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        window.releasedWhenClosed = NO;
        window.title = @"Window Effects Test";
        [window orderFront:nil];
        // Let LaunchServices publish the activation policy before another
        // process checks whether this is an ordinary application window.
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
        printf("%u\n", (uint32_t)window.windowNumber);
        fflush(stdout);
        // Let tests destroy the window while keeping the injected host alive.
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            char command;
            if (read(STDIN_FILENO, &command, 1) == 1 && command == 'c') {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [window close];
                    puts("closed"); fflush(stdout);
                });
            }
        });
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:60]];
    }
}
