#!/bin/bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run with sudo after restoring windows and stopping the user agent.' >&2; exit 1; }
destination='/Library/Application Support/WindowEffects'
[[ ! -L $destination ]] || { echo 'Refusing symlinked installation directory.' >&2; exit 1; }
rm -f /etc/sudoers.d/window-effects "$destination/loader" "$destination/payload.dylib"
if [[ -d $destination ]]; then rmdir "$destination"; fi
echo 'Backend files removed. Log out/in to unload the already-loaded payload.'
echo 'Existing SIP settings and unrelated sudoers entries were not changed.'
