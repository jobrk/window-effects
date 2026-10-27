# Window Effects

Remove macOS window shadows and dim inactive windows while AeroSpace handles
layout, workspaces and shortcuts. Defaults: no shadows, active opacity `1.0`,
inactive opacity `0.9`.

This is a small command-line tool, a user LaunchAgent and a Dock payload. It has
no yabai runtime dependency. It changes WindowServer appearance; it does not
remove titlebars, AppKit's titlebar rim or decorations drawn by an application.

## Requirements

- Apple Silicon, Xcode Command Line Tools and Python 3.
- AeroSpace 0.21.3-Beta or later for the watcher.
- Administrator access and the SIP/arm64e prerequisites needed for Dock injection,
  including `-arm64e_preview_abi`. See the
  [upstream prerequisites](https://github.com/asmvik/yabai/wiki/Disabling-System-Integrity-Protection).

The installers do not change SIP or boot arguments. This project uses private
APIs: live behavior is verified on macOS 26.6.2; macOS 27 is unverified. See
[COMPATIBILITY.md](COMPATIBILITY.md) for the tested scope.

## Build and install

```sh
make test
sudo ./scripts/install-backend.sh --enable-autoload
sudo "/Library/Application Support/WindowEffects/loader"
./scripts/install-user.sh
~/.local/bin/window-effects doctor
```

The backend is installed under `/Library/Application Support/WindowEffects`, owned
by root. The user installer writes `~/.local/bin/window-effects`, preserves an
existing `~/.config/window-effects/config.json`, and installs a LaunchAgent.
Neither installer starts the watcher.

`--enable-autoload` is optional. It installs a sudoers rule for the fixed loader
path, with no arguments and a SHA-256 digest tied to the installed binary. This
lets the watcher reload the payload after Dock restarts, using noninteractive
`sudo -n`. Without it, repeat the manual loader command after Dock restarts.

Start AeroSpace, then enable the watcher:

```sh
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/local.window-effects.plist"
```

The LaunchAgent starts at login. Keep other shadow/opacity controllers stopped.
If migrating from yabai, clear its effects before stopping it:
`yabai -m config window_opacity off` and `yabai -m config window_shadow on`.
Restart Dock before loading this payload to unload any previous scripting addition.

## Configure and use

The configuration file has four keys; see [config.example.json](config.example.json):

| Key | Meaning |
|---|---|
| `activeOpacity` | Focused-window opacity, from `0.1` to `1.0` |
| `inactiveOpacity` | Other managed windows' opacity, from `0.1` to `1.0` |
| `shadows` | Whether managed windows retain their WindowServer shadows |
| `excludedApps` | Application bundle IDs to leave unchanged |

A missing file uses defaults. Invalid values or unknown keys fail validation.
Restart the watcher after changing configuration.

```sh
window-effects check-config
window-effects doctor
window-effects apply                 # reconcile once with AeroSpace
window-effects watch                 # foreground watcher; Ctrl-C restores effects
window-effects inspect 123            # inspect a WindowServer window ID
window-effects set 123 0.9 off        # opacity and shadows on/off
window-effects restore 123            # restore one window
window-effects restore               # restore every window changed by the backend
```

`apply`, `watch` and `check-config` accept an optional configuration path.
Window selection comes from AeroSpace; only normal application windows on layer
zero may be changed. Exclusions and windows leaving that selection are restored.
Logs are in `~/Library/Logs/window-effects/`.

## Restore, upgrade or uninstall

Stop the watcher and restore before replacing a loaded backend:

```sh
launchctl bootout "gui/$(id -u)/local.window-effects"
window-effects restore
```

Rebuild and reinstall, restart Dock, load the backend, then bootstrap the watcher
again. Reinstall with `--enable-autoload` to refresh the permitted loader hash.
Changing the on-disk payload does not replace the copy already loaded into Dock.

To uninstall:

```sh
./scripts/uninstall-user.sh
sudo ./scripts/uninstall-backend.sh
```

The user uninstaller requires successful restoration before removing the CLI.
Config, logs and the restoration journal are retained. Restart Dock or log out
after removing the backend to unload its resident code.

Original values are saved before mutation in a private per-user directory at
`/tmp/window-effects-<uid>/originals.json`. The journal survives CLI and Dock
restarts; do not delete it before restoration. If the watcher is forcibly killed,
run `restore` manually. If the backend is unavailable, load it first.

## Read the code and run tests

| File | Responsibility |
|---|---|
| `src/main.m` | CLI, configuration, AeroSpace events and reconnection |
| `src/payload.m` | Serial Dock service, original-state journal, verified writes and restoration |
| `src/protocol.h` | Bounded JSON-over-Unix-socket transport and same-user checks |
| `src/skylight.h` | Private API declarations and shadow-tag operation |
| `src/loader.m` | arm64e bootstrap that loads the fixed payload into Dock |

Events trigger reconciliation with AeroSpace's current window list. A five-second
backend health check detects Dock restarts. The payload reads back writes, attempts
rollback after partial failure, and keeps failed restores for retry. Journal
entries pair window IDs with owner connections and are checked against the public
WindowServer list to avoid restoring stale or reused IDs.

`make test` uses a disposable host and a separate socket; it does not inject into
Dock. `make test-arm64e` also tests the payload in an arm64e host and requires the
arm64e boot prerequisite. With the production watcher stopped and backend loaded,
`python3 tests/live.py` tests a temporary foreign window against the real Dock.
Run these tests in a graphical login session. `make format` applies `.clang-format`.

The loader is adapted from yabai's MIT-licensed loader, with its original arm64e
attribution preserved. See [vendor/README.md](vendor/README.md) and the included
license. Window policy, protocol, service and tests are implemented here.
