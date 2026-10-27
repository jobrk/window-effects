# Window Effects

Build a small macOS companion to AeroSpace for window shadows and opacity.
No tiling, native Space manipulation, animations, or yabai runtime dependency.

1. [x] Prove direct SkyLight access against an owned window and a separate process.
   Direct cross-process writes returned success but readback did not change.
   Own-process opacity works; no-shadow tags require Dock even for owned windows.
2. [x] Implement a narrow Dock payload and loader with attributed
   upstream code, keeping all window policy outside Dock.
3. [x] Add apply/restore/doctor/watch commands and installation instructions.
4. [x] Finish tests and perform a live Dock test (administrator-authenticated loading).
   Own backend changed and restored a separate process's shadow and alpha with
   yabai's daemon stopped. Arm64 and arm64e integration tests pass.
5. [x] Commit a usable release with explicit compatibility evidence and limits.

Deferred acceptance: macOS 27 hardware/OS run, live AeroSpace integration, and a
clean Dock session without the older co-resident yabai library. These are recorded
in COMPATIBILITY.md and are not claimed as tested by the local release.

Current machine: macOS 26.6.2 (25G83), Apple Silicon. macOS 27 cannot be
runtime-validated here. Never mark it tested from an OS version check alone.

Keep the running desktop intact unless a short, reversible test is necessary.
Do not change SIP or install passwordless sudo rules automatically.
