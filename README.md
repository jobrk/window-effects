# Window Effects

A small macOS companion to AeroSpace: remove window shadows and make inactive
windows slightly transparent, with immediate changes and original-state restoration.

The default appearance matches this machine's former yabai setup: shadows off,
focused opacity `1.0`, inactive opacity `0.9`. AeroSpace owns window layout,
workspaces and shortcuts. Window Effects has no yabai runtime dependency.

## Requirements and status

- Apple Silicon Mac, Xcode Command Line Tools, Python 3 for tests/install scripts.
- AeroSpace 0.21.3-Beta or newer for `apply` and `watch`. Individual window commands
  and the backend do not require AeroSpace.
- Dock injection requires administrator authentication, partially disabled SIP,
  and the `-arm64e_preview_abi` boot argument. The installer never changes SIP or
  boot arguments. See [the upstream prerequisites](https://github.com/asmvik/yabai/wiki/Disabling-System-Integrity-Protection).
- Private macOS APIs are used. macOS 27 compatibility is **unverified**, not
  guaranteed by successful compilation or symbol lookup. See [COMPATIBILITY.md](COMPATIBILITY.md).

## Build and test

```sh
make
make test
```

On a machine with arm64e user binaries already enabled, `make test-arm64e` also
tests the backend in an arm64e host, matching Dock's pointer-authentication ABI.

The executable is `build/window-effects`. Both the loader and Dock payload are
built as **arm64e**; the ordinary CLI is arm64. There are no package dependencies.
The live Dock test has passed on macOS 26.6.2; see the exact scope in the
compatibility record.

`make test` loads the backend into a disposable application using a separate test
socket. It verifies actual opacity changes/readback, the expected rejection of
shadow changes outside Dock, rollback, original-value journaling, invalid requests,
configuration, reconnects and shutdown. It never injects into Dock or changes
other applications' windows. Run it in a logged-in graphical macOS session.

## Install

First stop any existing appearance controller before enabling ours. When migrating
from yabai, stop its service and restart Dock to unload the old injection; retain
your existing configuration until the migration is accepted.

Install the backend and load it once:

```sh
sudo ./scripts/install-backend.sh
sudo "/Library/Application Support/WindowEffects/loader"
build/window-effects doctor
```

The backend consists of two root-owned files in
`/Library/Application Support/WindowEffects`. Its only operations are appearance
inspection, setting, restoration, and status. It does not manipulate native Spaces
or scan Dock for function offsets.

Test the real Dock backend against one temporary application window:

```sh
make build/fixture
python3 tests/live.py
```

Install the user-side tool and startup definition:

```sh
./scripts/install-user.sh
~/.local/bin/window-effects check-config
~/.local/bin/window-effects apply
```

The user installer preserves an existing config. It does not start any process.
With AeroSpace running, start the appearance watcher:

```sh
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/local.window-effects.plist"
```

The LaunchAgent starts at login. The watcher follows AeroSpace focus/window events,
reconciles managed windows on reconnect, and restores effects when AeroSpace exits
or the watcher receives SIGINT/SIGTERM/SIGHUP. A lightweight five-second health
check detects a Dock restart; window updates are event-driven.

### Loading again after Dock restarts

Without extra authorization, repeat the `sudo .../loader` command after Dock
restarts. For unattended login/recovery, explicitly install the optional rule:

```sh
sudo ./scripts/install-backend.sh --enable-autoload
```

This adds `/etc/sudoers.d/window-effects`, permitting only the installed loader,
with no arguments and a SHA-256 digest tied to that signed build. The payload path
is fixed and root-owned. The watcher uses `sudo -n` and will never ask for a password.
Reinstall with this option after rebuilding the loader to update its digest.

## Commands and configuration

```sh
window-effects doctor
window-effects inspect 123
window-effects set 123 0.9 off     # window ID, opacity, shadows on/off
window-effects restore 123
window-effects restore           # all windows changed by this backend
window-effects apply             # one pass over AeroSpace-managed windows
window-effects watch             # foreground watcher; Ctrl-C restores effects
window-effects check-config
```

`apply`, `watch` and `check-config` accept an optional config path. Otherwise they
read `~/.config/window-effects/config.json`, using built-in defaults if absent.
See [config.example.json](config.example.json). Opacity must be between `0.1` and
`1.0`; unknown config keys and incorrect types are rejected. Restart the watcher
after editing its configuration.

Only layer-zero windows belonging to regular applications can be changed.
`apply` further restricts changes to windows listed by AeroSpace and honors bundle-ID
exclusions. Application-drawn shadows and title-bar removal are outside its scope.

The backend verifies setters by reading back the resulting state. A failed change
attempts to roll back immediately, reports whether that worked, and retains the
original snapshot for another restore attempt. Window IDs are paired with their
WindowServer owner connection to reject stale snapshots after app restarts.

Original values are journaled **before mutation** under
`/tmp/window-effects-<uid>/originals.json`, inside a mode-0700 directory. This survives
a CLI or Dock restart in the current login session. The socket accepts only peers
with the same UID. SIGKILL cannot trigger cleanup; run `restore` afterward. On a
reboot the old windows no longer exist. Do not delete the journal before restoration.

Logs: `~/Library/Logs/window-effects/{output,error}.log`. Check `doctor` when
effects are unavailable; its backend result distinguishes an installed CLI from a
successfully loaded payload. Private API failures leave a visible error rather than
silently reporting success.

## Upgrade and remove

Stop the watcher and restore before replacing a loaded payload:

```sh
launchctl bootout "gui/$(id -u)/local.window-effects"
window-effects restore
```

After rebuilding/reinstalling, restart Dock (or log out/in) to unload its old copy,
then load the new backend and bootstrap the watcher. Do not repeatedly inject an
already loaded payload; the server preserves its active endpoint and journal.

Uninstall in this order:

```sh
./scripts/uninstall-user.sh
sudo ./scripts/uninstall-backend.sh
```

The user uninstaller stops the agent and restores effects before removing the CLI.
It refuses to continue if restoration fails. Reload the backend and retry in that
case. Backend removal deletes only our two files and our optional sudoers rule;
log out/in afterward to unload the code already in Dock. Configuration and logs
are retained. Re-enabling SIP is a separate Recovery operation when no remaining
software requires it.

## Repository integration

Keep binaries and release tags here. Keep the appearance policy in dotfiles as
`window-effects/.config/window-effects/config.json`. Ansible can install a pinned
build and call the two installers; run the user installer without `become`, and
the backend installer with `become`. The optional autoload rule is an explicit
choice. Do not put binaries, SIP changes, or broad sudo rules in dotfiles.

The repository is currently local; no remote release URL is assumed. The existing
Ansible/dotfiles repositories have not been changed by this project implementation.

## Attribution

The small loader is adapted from yabai's MIT-licensed loader; its source commit,
license and the original arm64e attribution are in [vendor/](vendor/README.md).
The protocol, controller, appearance policy, payload service and tests are separate
implementations. SkyLight shadow tags and opacity calls follow the upstream
[appearance implementation](https://github.com/asmvik/yabai/blob/master/src/osax/payload.m).
