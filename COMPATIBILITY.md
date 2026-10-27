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
- **Live cutover passed on 2026-10-27 with AeroSpace 0.21.3-Beta.** Yabai and skhd
  were stopped and disabled. Dock was restarted, then only our backend was loaded.
  `lsof` showed our payload and no yabai payload in the fresh Dock process.
- `tests/live.py` changed a separate process's window from opacity `1.0` with a
  shadow to `0.63` without one, restored it, and returned the journal count to zero.
- Ghostty, Zen and Spotify run on AeroSpace workspaces 1, 2 and 3. Readback confirms
  no shadows, active opacity `1.0` and inactive opacity `0.9`; focus transitions
  update the values through the real AeroSpace event stream.
- All nine configured workspace bindings, send-without-following, fullscreen,
  floating, balance and reload were exercised with `trigger-binding`. Both resize
  axes in a nested layout changed real window frames by 50 pixels and reversed
  correctly. Physical shortcut handling and hover/popup behavior still need
  daily-use acceptance.
- Opening System Settings produced a floating window that retained its shadow and
  opacity `1.0`, and was absent from the helper's saved-window journal. Spotify was
  relaunched and its new window received the appearance policy.
- Stopping the watcher restored the three original appearances and emptied the
  journal. Restarting it reapplied the policy. Restarting Dock triggered automatic
  hash-pinned loading and restored the policy. Exiting AeroSpace restored original
  appearances; reopening it reconnected the watcher. AeroSpace window placement
  was reassigned after its restart; bindings reload config without restarting it.
- AeroSpace did not reliably expose temporary test apps invoked directly as CLI
  executables. Window Effects can only style normal windows exposed by AeroSpace;
  it does not repair AeroSpace's app detection or style OS panels globally.
- One built-in display was available. Sleep/wake, external display reconnection,
  native fullscreen/video popups and native Ctrl+Cmd dragging after app relaunch
  remain manual acceptance checks. No logout/reboot was forced during the cutover.

The initial cutover used runtime source `76e72b4`, dotfiles `a28d1ac` and Ansible
`a77a42c`. The final cleanup test found that private SkyLight getters can retain
stale values after a window closes. Version 0.1.1 (`332189a`) cross-checks journal
entries against the public WindowServer list and adds closed-window regression
tests; both arm64 and arm64e suites pass. The 0.1.1 payload was installed and
loaded into a fresh Dock: the observed stale entry was discarded, the live
foreign-window destruction test passed, and automatic Dock recovery plus focus
updates passed again with exactly three managed windows. Ansible `913df41` pins
this correction; final dotfiles revision is `728257d` (runtime config unchanged
from `a28d1ac`).

Desktop provisioning CI passed installation and a second run with `changed=0`,
`failed=0`: [run 40561726184](https://github.com/jobrk/ansible/actions/runs/40561726184/job/122392940020).
The broader Fedora-without-sudo job failed an unrelated Neovim Java prerequisite;
that full workstation workflow is not claimed green.

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
