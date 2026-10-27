# Compatibility

| Platform | Evidence |
|---|---|
| macOS 26.6.2 (25G83), Apple Silicon | Live Dock injection, shadow/opacity changes, restoration and AeroSpace 0.21.3-Beta integration verified with v0.1.1 |
| macOS 27.2 (26B123), Apple Silicon | Live v0.1.1 Dock backend, restoration, focus updates and Dock restart recovery verified with AeroSpace 0.21.3-Beta |
| Intel Macs | Unsupported by the loader/build |

On macOS 26.6.2, testing used a fresh Dock without yabai's payload. Verified:

- Opacity and shadow changes to a separate application's window, with readback.
- Original-state journaling, repeated updates, restoration and closed-window cleanup.
- Focus updates and app exclusions through AeroSpace's actual event stream.
- Watcher shutdown, AeroSpace exit/restart and automatic loading after Dock restart.
- Disposable-host integration tests on arm64 and arm64e.

On macOS 27.2 (26B123), the existing v0.1.1 installation started after the OS
upgrade and reboot. Verified without yabai's daemon or Dock payload:

- Shadow/opacity changes and restoration on a separate process's window.
- Closed-window cleanup and an empty journal after watcher shutdown.
- Original appearance restoration on real application windows, followed by
  reapplication and focus dimming across two AeroSpace workspaces.
- Automatic backend loading and appearance recovery after restarting Dock.
- AeroSpace exit restores appearance; restart reconnects the watcher and
  reapplies effects. System Settings floats and retains its original appearance
  while focused and unfocused, without entering the restoration journal.
- Source build and disposable-host integration tests on arm64 and arm64e.

These results apply to the exact builds listed; other macOS 27 builds have not
been tested.

SIP/arm64e prerequisites are required even though no yabai process is involved.
Public WindowServer enumeration is needed for cleanup: private SkyLight getters
can keep returning stale data after a window closes.

CI builds and runs disposable-host tests. It does not validate privileged Dock
injection, visual rendering, login, sleep/wake, external displays or native
fullscreen interactions. These need interactive testing on the target OS build.
A successful compile or symbol lookup is not proof of compatibility.

Window Effects only handles ordinary windows exposed by AeroSpace. Application
detection limitations belong to AeroSpace. WindowServer shadows, AppKit titlebar
rims and application-drawn effects are separate; only the first is controlled here.
