#!/bin/bash
set -euo pipefail
[[ $EUID -ne 0 ]] || { echo 'Run as your normal user, without sudo.' >&2; exit 1; }
launchctl bootout "gui/$(id -u)/local.window-effects" 2>/dev/null || true
if [[ -x $HOME/.local/bin/window-effects ]]; then
    "$HOME/.local/bin/window-effects" restore || {
        echo 'Restore failed. Reload the backend and retry before deleting the journal.' >&2
        exit 1
    }
fi
rm -f "$HOME/Library/LaunchAgents/local.window-effects.plist" "$HOME/.local/bin/window-effects"
echo 'Removed the user agent and CLI. Preserved configuration, logs and restoration journal.'
echo 'Backend removal (after restoration): sudo ./scripts/uninstall-backend.sh'
