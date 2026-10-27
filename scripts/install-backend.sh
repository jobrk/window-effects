#!/bin/bash
set -euo pipefail
if [[ $EUID -ne 0 ]]; then
    echo 'Run this script with sudo after make test.' >&2
    exit 1
fi
if [[ $# -gt 1 || ($# -eq 1 && $1 != --enable-autoload) ]]; then
    echo "Usage: sudo $0 [--enable-autoload]" >&2
    exit 2
fi
repo=$(cd "$(dirname "$0")/.." && pwd)
destination='/Library/Application Support/WindowEffects'
for binary in loader payload.dylib; do
    [[ -f $repo/build/$binary ]] || { echo 'Run make first as your normal user.' >&2; exit 1; }
done
if [[ -L $destination || (-e $destination && ! -d $destination) ]]; then
    echo "Refusing unexpected installation path: $destination" >&2
    exit 1
fi
install -d -o root -g wheel -m 755 "$destination"
install -o root -g wheel -m 755 "$repo/build/loader" "$destination/loader"
install -o root -g wheel -m 755 "$repo/build/payload.dylib" "$destination/payload.dylib"
codesign --force --sign - "$destination/loader"
codesign --force --sign - "$destination/payload.dylib"

# Optional: permit precisely this signed loader, with no arguments. No general
# sudo access, no shell, no arbitrary payload path, and a hash tied to this build.
rule='/etc/sudoers.d/window-effects'
if [[ ${1:-} == --enable-autoload ]]; then
    account=${SUDO_USER:-}
    if [[ ! $account =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ || $account == root ]]; then
        echo 'Autoload requires sudo from your normal desktop account.' >&2
        exit 1
    fi
    digest=$(shasum -a 256 "$destination/loader" | awk '{print $1}')
    temporary=$(mktemp /private/tmp/window-effects-sudoers.XXXXXX)
    trap 'rm -f "$temporary"' EXIT
    printf '# Managed by window-effects; only the fixed, root-owned loader.\n%s ALL=(root) NOPASSWD: sha256:%s /Library/Application\\ Support/WindowEffects/loader ""\n' \
        "$account" "$digest" > "$temporary"
    chmod 440 "$temporary"
    visudo -cf "$temporary"
    install -d -o root -g wheel -m 755 /etc/sudoers.d
    install -o root -g wheel -m 440 "$temporary" "$rule"
    echo 'Installed the narrowly scoped autoload rule.'
elif [[ -e $rule ]]; then
    echo 'An existing autoload rule was left unchanged; its hash may need updating.'
fi
echo 'Backend installed. No code has been injected and no services were started.'
echo 'Load it with: sudo "/Library/Application Support/WindowEffects/loader"'
echo 'After upgrading a loaded payload: restore effects and restart Dock before loading the new version.'
