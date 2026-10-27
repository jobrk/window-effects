# Compatibility evidence

## macOS 26.6.2 (25G83), Apple Silicon

- Builds with Apple clang 17 / Xcode's macOS 26 SDK.
- Direct cross-process setters returned success but did not change either alpha
  or shadow state. `tests/probe.m` records and checks this behavior.
- A backend inside the window-owning test process changed and restored opacity.
  The no-shadow tag was ignored even there; the operation correctly failed and
  rolled back its partial opacity change.
- Integration tests pass for readback, original-state journaling, restoration,
  invalid input, separate test socket, reconnects, and watcher termination.
  Both arm64 and arm64e disposable hosts were exercised.
- The first Dock-load attempt failed because the loader was built arm64 rather
  than arm64e. The Makefile now builds both loader and payload as arm64e.
- **Live Dock validation passed:** a separate process's window went from opacity
  `1.0` with a shadow to `0.63` without a shadow, then returned to its original
  state. The saved-window count returned to zero. Yabai's daemon was stopped for
  the test and restarted afterward. Its previously injected library was still
  resident in Dock; our implementation makes no calls to that library or socket.
- AeroSpace itself is not installed on this development machine. Its event-stream
  integration is tested with a controlled CLI fixture; real AeroSpace GUI testing
  and a fresh Dock session without the older resident library remain acceptance
  checks before a full desktop migration.

## macOS 27

Not runtime-tested: this development machine runs macOS 26.6.2. A successful build
is not evidence of Dock injection or window-operation compatibility.

Acceptance requires a clean Dock session without yabai's injected payload, then:

1. Install/load our backend and verify `window-effects doctor` reports its version.
2. Run `tests/live.py` to change and restore a separate process's real window.
3. Run AeroSpace with Ghostty, Zen and Spotify; test focus, new windows, dialogs,
   exclusions, sleep/wake, and display reconnection.
4. Stop the watcher and verify restoration. Restart AeroSpace and Dock separately
   and verify recovery, including the optional hash-pinned autoload rule if enabled.
5. Record the exact macOS build, project commit and results here.

This project avoids yabai's native-Space offsets, but still depends on private
SkyLight APIs and Dock injection. Future OS changes may require a code update.
