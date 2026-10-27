# Window Effects

Build a small macOS companion to AeroSpace for window shadows and opacity.
No tiling, native Space manipulation, animations, or yabai runtime dependency.

1. Prove direct SkyLight access against an owned window and a separate process.
2. If necessary, implement a narrow Dock payload and loader with attributed
   upstream code, keeping all window policy outside Dock.
3. Add apply/restore/doctor/watch commands and installation instructions.
4. Test changes and restoration, malformed inputs, reconnects, and process exit.
5. Commit a usable release with explicit compatibility evidence and limits.

Current machine: macOS 26.6.2 (25G83), Apple Silicon. macOS 27 cannot be
runtime-validated here. Never mark it tested from an OS version check alone.

Keep the running desktop intact unless a short, reversible test is necessary.
Do not change SIP or install passwordless sudo rules automatically.
