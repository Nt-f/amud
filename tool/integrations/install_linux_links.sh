#!/usr/bin/env bash
# Register the installed bundle's amud:// handler for this user, no root needed.
set -euo pipefail
AMUD_EXECUTABLE="$(realpath "${1:?Usage: install_linux_links.sh /path/to/amud}")"
AMUD_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
mkdir -p "$AMUD_DATA_DIR/applications"
python3 - "$AMUD_EXECUTABLE" "$AMUD_DATA_DIR/applications/page.amud.desktop" <<'PY'
import sys
from pathlib import Path
# Exec fields have their own escape syntax. Quote the path, escape literal
# percent expansion, and do not allow newlines in a desktop entry.
p = sys.argv[1]
if '\n' in p or '\r' in p:
    raise SystemExit('Invalid executable path')
p = p.replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$').replace('%', '%%')
Path(sys.argv[2]).write_text('[Desktop Entry]\nType=Application\nName=Amud\nExec="' + p + '" %u\nMimeType=x-scheme-handler/amud;\nCategories=Education;\nTerminal=false\n')
PY
xdg-mime default page.amud.desktop x-scheme-handler/amud
