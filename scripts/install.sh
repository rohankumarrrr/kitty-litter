#!/bin/zsh
# Builds Shades.app and swaps it into /Applications, then restarts it. The running copy is only
# touched once the new one is built and properly signed, so a failed build changes nothing.
#
# macOS may ask whether codesign can use your signing key. Choose Always Allow, and it won't
# ask again.
set -euo pipefail

root="${0:A:h:h}"
app=/Applications/Shades.app
next="$(mktemp -d)"
trap 'rm -rf "$next"' EXIT

"$root/scripts/bundle.sh" "$next"
codesign --verify --deep --strict "$next/Shades.app"

# With a stable identity, permissions carry over. Without one, they'd all be lost, so that takes asking for.
if ! codesign -dvv "$next/Shades.app" 2>&1 | grep -q '^Authority='; then
  if [[ "${1:-}" != "--ad-hoc" ]]; then
    echo "This build is signed ad hoc, so macOS would forget Shades' permissions."
    echo "Run scripts/make-dev-cert.sh first, or pass --ad-hoc to install it anyway."
    exit 1
  fi
fi

pkill -x Shades 2>/dev/null || true
while pgrep -x Shades >/dev/null; do sleep 0.1; done
rm -rf "$app"
ditto "$next/Shades.app" "$app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
open "$app"
echo "Installed and running."
