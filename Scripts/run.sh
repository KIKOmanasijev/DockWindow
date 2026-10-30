#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./Scripts/build-app.sh
pkill -x DockWindow || true
open "$HOME/Applications/DockWindow.app"
