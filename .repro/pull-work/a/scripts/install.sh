#!/bin/zsh
# Builds Shades.app and swaps it into /Applications, then restarts it. The running copy is only
# touched once the new one is built and properly signed. The old copy is kept, and if the new one
# doesn't come up and report in, the old one goes back.
#
#   scripts/install.sh              # build and install
#   scripts/install.sh --ad-hoc     # allow a build with no stable signature, losing permissions
#   scripts/install.sh --rollback   # put the last working copy back
#   scripts/install.sh --pull       # stop if there's uncommitted work, pull, then build and install
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
  # Copied alongside first, so running out of disk or any other failure leaves the old copy where it is.
  rm -rf "$app.new"
  ditto "$1" "$app.new"
  rm -rf "$app"
  mv "$app.new" "$app"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
}

restore() {
  if [[ ! -d "$keep" ]]; then
    echo "There's no earlier copy to go back to."
    exit 1
  fi
  stop_running
  # A report from the copy that's gone would look like one from the copy coming back.
  rm -f "$health"
  put_in_place "$keep"
  open "$app"
}

if [[ "${1:-}" == "--rollback" ]]; then
  restore
  echo "Back on the last working copy."
  exit 0
fi

if [[ "${1:-}" == "--pull" ]]; then
  if [[ -n "$(git -C "$root" status --porcelain)" ]]; then
    echo "$root has uncommitted work, so nothing was installed."
    exit 1
  fi
  git -C "$root" pull --ff-only
  # Run what was just pulled, not the copy of this script that's already going.
  exec "$root/scripts/install.sh"
fi
echo "WOULD INSTALL: branch=$(git -C "$root" rev-parse --abbrev-ref HEAD) head=$(git -C "$root" log -1 --format=%s)"
exit 0
