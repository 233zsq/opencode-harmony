#!/usr/bin/env bash
# Provision the pinned search runtime inside this application's owned jail only.
set -euo pipefail
JAIL=/var/lib/opencode-harmony-root
APP=$JAIL/home/ubuntu/opencode-harmony-service
EXPECTED=1c9297be4a084eea7ecaedf93eb03d058d6faae29bbc57ecdaf5063921491599
[ "$(id -u)" = 0 ] && [ -f "$JAIL/.opencode-harmony-jail-owned" ] || exit 1
[ "$#" = 1 ] && [ -f "$1" ] && [ ! -L "$1" ] || { echo 'Pass the verified official ripgrep 15.1.0 x64 musl archive' >&2; exit 1; }
printf '%s  %s\n' "$EXPECTED" "$1" | sha256sum -c -
for p in "$JAIL" "$APP" "$APP/cache" "$APP/cache/opencode" "$APP/cache/opencode/bin"; do
 [ ! -L "$p" ] || exit 1
 case "$(realpath -m "$p")" in "$JAIL"|"$JAIL"/*) ;; *) exit 1 ;; esac
done
umask 077
TEMP=$(mktemp -d "$APP/tmp/search-install-XXXXXX")
trap 'rm -f "$TEMP/rg"; rmdir "$TEMP"' EXIT
tar -xOzf "$1" ripgrep-15.1.0-x86_64-unknown-linux-musl/rg > "$TEMP/rg"
chmod 700 "$TEMP/rg"
"$TEMP/rg" --version | head -n 1 | grep -E '^ripgrep 15\.1\.0( |$)'
DEST=$APP/cache/opencode/bin/rg
[ ! -L "$DEST" ] || exit 1
if [ -e "$DEST" ]; then cmp "$TEMP/rg" "$DEST"; echo 'Pinned search dependency already installed'; exit 0; fi
install -d -o oc-harmony-agent -g oc-harmony-agent -m 700 "$APP/cache" "$APP/cache/opencode" "$APP/cache/opencode/bin"
install -o oc-harmony-agent -g oc-harmony-agent -m 755 "$TEMP/rg" "$DEST"
echo 'Installed pinned search dependency; no services restarted'
