# Window Effects

Build a small macOS companion to AeroSpace for window shadows and opacity.
No tiling, native Space manipulation, animations, or yabai runtime dependency.

1. [x] Prove direct SkyLight access against an owned window and a separate process.
   Direct cross-process writes returned success but readback did not change.
   Own-process opacity works; no-shadow tags require Dock even for owned windows.
2. [x] Implement a narrow Dock payload and loader with attributed
   upstream code, keeping all window policy outside Dock.
3. [x] Add apply/restore/doctor/watch commands and installation instructions.
4. [ ] Finish tests and perform a live Dock test (requires administrator authentication).
5. [ ] Commit a usable release with explicit compatibility evidence and limits.

Current machine: macOS 26.6.2 (25G83), Apple Silicon. macOS 27 cannot be
runtime-validated here. Never mark it tested from an OS version check alone.

Keep the running desktop intact unless a short, reversible test is necessary.
Do not change SIP or install passwordless sudo rules automatically.
