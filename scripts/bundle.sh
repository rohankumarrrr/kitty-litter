#!/bin/zsh
# Builds a release Shades.app, which macOS permissions need: they attach to a signed
# bundle, not to a bare binary.
#
#   scripts/bundle.sh [output-folder]        # defaults to build/
#   scripts/bundle.sh /Applications          # installs it
#
# It signs with the first identity it finds, in this order:
#   1. $SHADES_SIGN_IDENTITY, if you set it
#   2. "Shades Dev", the self-signed certificate from scripts/make-dev-cert.sh
#   3. Your "Apple Development" or "Developer ID Application" certificate
#   4. Ad hoc, with a warning. An ad-hoc signature changes on every build, so macOS
#      forgets its permissions each time. Run scripts/make-dev-cert.sh to stop that.
set -euo pipefail

root="${0:A:h:h}"
out="${1:-$root/build}"
app="$out/Shades.app"

cd "$root"
swift build -c release --product shades
bin="$(swift build -c release --product shades --show-bin-path)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/shades" "$app/Contents/MacOS/Shades"
cp assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

# The cleanup model's runtime. Without it the app won't launch.
mkdir -p "$app/Contents/Frameworks"
ditto "$bin/llama.framework" "$app/Contents/Frameworks/llama.framework"

# Resources from dependencies, if they have any.
for bundle in "$bin"/*.bundle(N); do
  cp -R "$bundle" "$app/Contents/Resources/"
done

version="$(git describe --tags --always 2>/dev/null || echo 0.1.0)"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>The Kitty Litter</string>
    <key>CFBundleDisplayName</key>
    <string>The Kitty Litter</string>
    <key>CFBundleIdentifier</key>
    <string>me.rohan-is.shades</string>
    <key>CFBundleExecutable</key>
    <string>Shades</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>$version</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>The Kitty Litter listens only while you hold your talk or dictate key, and your voice stays on your Mac.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>So the cat can read the page you're looking at when you ask.</string>
</dict>
</plist>
PLIST
plutil -lint -s "$app/Contents/Info.plist"

find_identity() {
  local identities
  identities="$(security find-identity -p codesigning 2>/dev/null || true)"
  if [[ -n "${SHADES_SIGN_IDENTITY:-}" ]]; then
    print -r -- "$SHADES_SIGN_IDENTITY"
    return
  fi
  local wanted
  for wanted in '"Shades Dev"' '"Apple Development' '"Developer ID Application'; do
    # The certificate's hash, so two with the same name can't make signing ambiguous.
    local match="$(print -r -- "$identities" | grep -F -- "$wanted" | head -1 | awk '{print $2}')"
    if [[ -n "$match" ]]; then
      print -r -- "$match"
      return
    fi
  done
}

identity="$(find_identity)"
if [[ -n "$identity" ]]; then
  codesign --force --sign "$identity" "$app/Contents/Frameworks/llama.framework"
  codesign --force --sign "$identity" --identifier me.rohan-is.shades "$app"
  echo "Signed with $(security find-identity -p codesigning 2>/dev/null | grep -F -- "$identity" | head -1 | sed -E 's/.*"(.*)".*/\1/')."
else
  codesign --force --sign - "$app/Contents/Frameworks/llama.framework"
  codesign --force --sign - --identifier me.rohan-is.shades "$app"
  echo "Signed ad hoc, so macOS will forget this app's permissions on every rebuild."
  echo "Run scripts/make-dev-cert.sh once to fix that."
fi

codesign --verify --deep --strict "$app"
echo "Built $app"
