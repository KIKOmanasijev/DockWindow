#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift package resolve
swift build -c release
bin=$(swift build -c release --show-bin-path)
app="$HOME/Applications/DogBar.app"
mkdir -p "$HOME/Applications"
staging=$(mktemp -d "$HOME/Applications/.DogBar.XXXXXX")
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/DogBar.app/Contents/MacOS" "$staging/DogBar.app/Contents/Resources"
cp "$bin/DogBar" "$staging/DogBar.app/Contents/MacOS/"
cp Resources/AppIcon.icns "$staging/DogBar.app/Contents/Resources/"
cp Resources/Info.plist "$staging/DogBar.app/Contents/"
/usr/libexec/PlistBuddy -c "Add :DogBarBuildRevision string $(git rev-parse --short HEAD)" "$staging/DogBar.app/Contents/Info.plist"
# Telemetry tags events with this, so local installs can be filtered out of real usage.
/usr/libexec/PlistBuddy -c "Add :DogBarBuildChannel string development" "$staging/DogBar.app/Contents/Info.plist"
# Local builds follow the preview update channel. The signed bundle, not user defaults, sets it.
/usr/libexec/PlistBuddy -c "Add :DogBarUpdateChannel string preview" "$staging/DogBar.app/Contents/Info.plist"
# Self-signed development identities can sign stable designated requirements even
# when system trust policy excludes them from find-identity's valid-only results.
if security find-identity -p codesigning | /usr/bin/grep -q '"DockWindow Dev"'; then
 identity='DockWindow Dev'
else
 print -u2 'WARNING: DockWindow Dev signing identity unavailable. Ad-hoc signing can reset permissions on rebuild, and updates stay disabled.'
 identity=-
fi
# Embeds the pinned Sparkle.framework and signs its helpers inside out. No --deep signing.
/usr/bin/python3 Scripts/sparkle_packaging.py embed --app "$staging/DogBar.app" --scratch .build --identity "$identity"
if [[ $identity == - ]]; then
 codesign --force --entitlements Resources/DogBar-SelfSigned.entitlements --sign - "$staging/DogBar.app"
else
 codesign --force --entitlements Resources/DogBar-SelfSigned.entitlements --options runtime --timestamp=none --sign "$identity" "$staging/DogBar.app"
 leaf=$(codesign --display --extract-certificates="$staging/cert" "$staging/DogBar.app" 2>/dev/null; /usr/bin/openssl x509 -inform DER -in "$staging/cert0" -noout -fingerprint -sha1 | /usr/bin/sed 's/.*=//; s/://g')
 /usr/bin/python3 Scripts/sparkle_packaging.py verify --app "$staging/DogBar.app" --requirement "certificate leaf = H\"$leaf\""
fi
codesign --verify --deep --strict "$staging/DogBar.app"
# One-time migration: builds before the rename installed DockWindow.app (bundle ID
# com.dockwindow.app). Quit it first so it restores the native Dock, then leave it for
# you to delete. Its permissions and settings do not carry over to the new bundle ID.
if /usr/bin/pgrep -x DockWindow >/dev/null; then
 /usr/bin/osascript -e 'tell application id "com.dockwindow.app" to quit'
 for task_quit_attempt in {1..300}; do
  if ! /usr/bin/pgrep -x DockWindow >/dev/null; then break; fi
  /bin/sleep 0.1
 done
 if /usr/bin/pgrep -x DockWindow >/dev/null; then
  print -u2 'The old DockWindow app is still running. Installation stopped so it can restore the Dock.'
  exit 1
 fi
fi
if [[ -e "$HOME/Applications/DockWindow.app" ]]; then
 print -u2 "Note: the old $HOME/Applications/DockWindow.app is no longer used. Delete it, and remove its entries in System Settings > Privacy & Security."
fi
# A running app must finish exact native Dock restoration before its bundle is replaced.
if /usr/bin/pgrep -x DogBar >/dev/null; then
 /usr/bin/osascript -e 'tell application id "dev.hristijan.dogbar" to quit'
 # The quit Apple event can return before asynchronous native Dock restoration.
 for task_quit_attempt in {1..300}; do
  if ! /usr/bin/pgrep -x DogBar >/dev/null; then break; fi
  /bin/sleep 0.1
 done
 if /usr/bin/pgrep -x DogBar >/dev/null; then
  print -u2 'DogBar is still running. Installation stopped so restoration can finish.'
  exit 1
 fi
fi
rm -rf "$app"
mv "$staging/DogBar.app" "$app"
print "Installed $app"
