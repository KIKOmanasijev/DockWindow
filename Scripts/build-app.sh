#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
bin=$(swift build -c release --show-bin-path)
app="$HOME/Applications/DockWindow.app"
mkdir -p "$HOME/Applications"
staging=$(mktemp -d "$HOME/Applications/.DockWindow.XXXXXX")
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/DockWindow.app/Contents/MacOS" "$staging/DockWindow.app/Contents/Resources"
cp "$bin/DockWindow" "$staging/DockWindow.app/Contents/MacOS/"
cp Resources/AppIcon.icns "$staging/DockWindow.app/Contents/Resources/"
cp Resources/Info.plist "$staging/DockWindow.app/Contents/"
if security find-identity -v -p codesigning | /usr/bin/grep -q '"DockWindow Dev"'; then
 codesign --force --deep --entitlements Resources/DockWindow.entitlements --options runtime --sign 'DockWindow Dev' "$staging/DockWindow.app"
else
 print -u2 'WARNING: DockWindow Dev certificate missing. Ad-hoc signing can reset permissions on rebuild.'
 codesign --force --deep --entitlements Resources/DockWindow.entitlements --sign - "$staging/DockWindow.app"
fi
# A running app must finish exact native Dock restoration before its bundle is replaced.
if /usr/bin/pgrep -x DockWindow >/dev/null; then
 /usr/bin/osascript -e 'tell application id "com.dockwindow.app" to quit'
 if /usr/bin/pgrep -x DockWindow >/dev/null; then
  print -u2 'DockWindow is still running. Installation stopped so restoration can finish.'
  exit 1
 fi
fi
rm -rf "$app"
mv "$staging/DockWindow.app" "$app"
print "Installed $app"
