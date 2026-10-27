#!/bin/bash
set -euo pipefail
[[ $EUID -ne 0 ]] || { echo 'Run as your normal user, without sudo.' >&2; exit 1; }
[[ $# -eq 0 ]] || { echo "Usage: $0" >&2; exit 2; }
repo=$(cd "$(dirname "$0")/.." && pwd)
[[ -x $repo/build/window-effects ]] || { echo 'Run make first.' >&2; exit 1; }
install -d "$HOME/.local/bin" "$HOME/.config/window-effects" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/window-effects"
install -m 755 "$repo/build/window-effects" "$HOME/.local/bin/window-effects"
if [[ ! -e $HOME/.config/window-effects/config.json ]]; then
    install -m 644 "$repo/config.example.json" "$HOME/.config/window-effects/config.json"
fi
python3 - <<'PY'
from pathlib import Path
import plistlib
home = Path.home()
agent = {
    'Label': 'local.window-effects',
    'ProgramArguments': [str(home / '.local/bin/window-effects'), 'watch'],
    'RunAtLoad': True,
    'KeepAlive': {'SuccessfulExit': False},
    'ThrottleInterval': 10,
    'StandardOutPath': str(home / 'Library/Logs/window-effects/output.log'),
    'StandardErrorPath': str(home / 'Library/Logs/window-effects/error.log'),
}
with (home / 'Library/LaunchAgents/local.window-effects.plist').open('wb') as f:
    plistlib.dump(agent, f)
PY
echo 'Installed CLI, config (if missing), and LaunchAgent. Nothing started.'
echo 'After loading the backend and starting AeroSpace:'
echo 'launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/local.window-effects.plist"'
