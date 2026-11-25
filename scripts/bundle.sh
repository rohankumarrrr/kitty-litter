#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
source "$root/scripts/signing.sh"
out="${1:-$root/build}"
app="$out/Shades.app"

cd "$root"
swift build -c release --product shades
bin="$(swift build -c release --product shades --show-bin-path)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/shades" "$app/Contents/MacOS/Shades"
cp assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

mkdir -p "$app/Contents/Frameworks"
ditto "$bin/llama.framework" "$app/Contents/Frameworks/llama.framework"

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
    <string>The Kitty Litter listens only while you hold your talk or dictate key, or from pressing a mic until you press it again, and your voice stays on your Mac.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>So the cat can read the page you're looking at when you ask.</string>
</dict>
</plist>
PLIST
plutil -lint -s "$app/Contents/Info.plist"

identity="${SHADES_SIGN_IDENTITY:-$(signing_identity "$(security find-identity -v -p codesigning 2>/dev/null || true)")}"
if [[ -n "$identity" ]]; then
  codesign --force --sign "$identity" "$app/Contents/Frameworks/llama.framework"
  codesign --force --sign "$identity" --identifier me.rohan-is.shades "$app"
  echo "Signed with $(signing_kind "$(security find-identity -p codesigning 2>/dev/null || true)" "$identity")."
else
  codesign --force --sign - "$app/Contents/Frameworks/llama.framework"
  codesign --force --sign - --identifier me.rohan-is.shades "$app"
  echo "Signed ad hoc, so macOS will forget this app's permissions on every rebuild."
  echo "Run scripts/make-dev-cert.sh once to fix that."
fi

codesign --verify --deep --strict "$app"
echo "Built $app"
