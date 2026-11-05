#!/bin/zsh
# Builds Shades.app and swaps it into /Applications, then restarts it. The running copy is only
# touched once the new one is built and properly signed. The old copy is kept, and if the new one
# doesn't come up and report in, the old one goes back.
#
#   scripts/install.sh              # build and install
#   scripts/install.sh --ad-hoc     # allow a build with no stable signature, losing permissions
#   scripts/install.sh --rollback   # put the last working copy back
#
# macOS may ask whether codesign can use your signing key. Choose Always Allow, and it won't
# ask again.
set -euo pipefail

root="${0:A:h:h}"
app=/Applications/Shades.app
data="$HOME/Library/Application Support/shades"
keep="$data/last-good/Shades.app"
health="$data/health.json"
wait_seconds="${SHADES_HEALTH_SECONDS:-30}"

stop_running() {
  pkill -x Shades 2>/dev/null || true
  while pgrep -x Shades >/dev/null; do sleep 0.1; done
}

put_in_place() {
  rm -rf "$app"
  ditto "$1" "$app"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
}

restore() {
  if [[ ! -d "$keep" ]]; then
    echo "There's no earlier copy to go back to."
    exit 1
  fi
  stop_running
  put_in_place "$keep"
  open "$app"
}

if [[ "${1:-}" == "--rollback" ]]; then
  restore
  echo "Back on the last working copy."
  exit 0
fi

next="$(mktemp -d)"
trap 'rm -rf "$next"' EXIT

"$root/scripts/bundle.sh" "$next"
codesign --verify --deep --strict "$next/Shades.app"

# With a stable identity, permissions carry over. Without one, they'd all be lost, so that takes asking for.
# Read into a variable first: piping this into grep -q can fail by itself under pipefail.
signature="$(codesign -dvv "$next/Shades.app" 2>&1)"
if [[ "$signature" != *"Authority="* && "${1:-}" != "--ad-hoc" ]]; then
  echo "This build is signed ad hoc, so macOS would forget Shades' permissions."
  echo "Run scripts/make-dev-cert.sh first, or pass --ad-hoc to install it anyway."
  exit 1
fi

stop_running
if [[ -d "$app" ]]; then
  mkdir -p "${keep:h}"
  rm -rf "$keep"
  ditto "$app" "$keep"
fi
put_in_place "$next/Shades.app"

# The app writes this once it's up and has checked itself. A problem it finds, such as a
# permission that's off, isn't a reason to go back: not coming up at all is.
rm -f "$health"
open "$app"
deadline=$(( SECONDS + wait_seconds ))
while (( SECONDS < deadline )); do
  if [[ -f "$health" ]] && pgrep -x Shades >/dev/null; then
    echo "Installed and running."
    exit 0
  fi
  sleep 0.5
done

echo "The new copy didn't come up within $wait_seconds seconds, so the last working copy is going back."
restore
exit 1
