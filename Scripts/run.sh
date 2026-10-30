#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./Scripts/build-app.sh
open -n "$HOME/Applications/DockWindow.app"
