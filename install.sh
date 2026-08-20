#!/bin/bash

# zamecki.antigravity installer.
#
# Adds the Antigravity entry to the Defaults -> Agent menu and installs the
# omarchy-default-agent / omarchy-agent wrappers that know how to launch agy.
# Idempotent: safe to run again after `omarchy refresh`.

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MENU_FILE="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
MENU_ID="setup.default.agent.antigravity"
BIN_DIR="$HOME/.local/bin"
WRAPPERS=(
  "$PLUGIN_DIR/wrappers/omarchy-default-agent"
  "$PLUGIN_DIR/wrappers/omarchy-agent"
  "$PLUGIN_DIR/wrappers/omarchy-agent-usage-update"
)
COLLECTOR="$PLUGIN_DIR/bin/omarchy-agent-usage-antigravity"

mkdir -p "$(dirname "$MENU_FILE")" "$BIN_DIR"

# --- Icon Font --------------------------------------------------------------
FONT_SRC="$PLUGIN_DIR/fonts/omarchy-antigravity.ttf"
FONT_DIR="$HOME/.local/share/fonts"
if [[ -f $FONT_SRC ]]; then
  mkdir -p "$FONT_DIR"
  install -m 0644 "$FONT_SRC" "$FONT_DIR/omarchy-antigravity.ttf"
  if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
  fi
  echo "font: installed omarchy-antigravity.ttf into $FONT_DIR"
fi

# --- Menu row ---------------------------------------------------------------
if [[ ! -f $MENU_FILE ]]; then
  printf '{\n}\n' >"$MENU_FILE"
fi
python3 - "$MENU_FILE" "$MENU_ID" <<'EOF'
import re, sys

path, key = sys.argv[1], sys.argv[2]
with open(path) as fh:
    content = fh.read()

row = (
    '  "' + key + '": {"icon":"\\ue908","iconFont":"omarchy-antigravity","label":"Antigravity",'
    '"checked":"[[ \\"$(omarchy-default-agent)\\" == \\"antigravity\\" ]]",'
    '"action":"omarchy-default-agent antigravity"}'
)

if re.search(r'^[ \t]*"' + re.escape(key) + r'"\s*:', content, flags=re.MULTILINE):
    new_content = re.sub(
        r'^[ \t]*"' + re.escape(key) + r'"\s*:.*?(?=,\s*\n|\n\s*\})',
        lambda m: row,
        content,
        flags=re.MULTILINE
    )
    with open(path, "w") as fh:
        fh.write(new_content)
    print("menu: updated " + key)
else:
    stripped = content.rstrip()
    if not stripped.endswith("}"):
        print("menu: refusing to edit malformed file (does not end with '}')", file=sys.stderr)
        sys.exit(1)

    head = stripped[:-1].rstrip()
    if head.endswith("{") or head.endswith(",\n") or head.endswith(","):
        new_content = head + "\n" + row + "\n}\n"
    else:
        new_content = head + ",\n" + row + "\n}\n"
    with open(path, "w") as fh:
        fh.write(new_content)
    print("menu: added " + key)
EOF

# --- Wrappers ---------------------------------------------------------------
for wrapper in "${WRAPPERS[@]}"; do
  name=$(basename "$wrapper")
  dst="$BIN_DIR/$name"
  if [[ -e $dst ]] && ! cmp -s "$dst" "$wrapper"; then
    echo "wrapper: backing up $dst to $dst.orig"
    cp "$dst" "$dst.orig"
  fi
  install -m 0755 "$wrapper" "$dst"
  echo "wrapper: installed $dst"
done

# --- Collector --------------------------------------------------------------
# The Service.qml invokes the collector by bare name, so it must land on PATH
# next to the wrappers, just like the packaged collectors in /usr/share/omarchy/bin.
if [[ -e $BIN_DIR/omarchy-agent-usage-antigravity ]] \
  && ! cmp -s "$BIN_DIR/omarchy-agent-usage-antigravity" "$COLLECTOR"; then
  echo "collector: backing up $BIN_DIR/omarchy-agent-usage-antigravity to .orig"
  cp "$BIN_DIR/omarchy-agent-usage-antigravity" "$BIN_DIR/omarchy-agent-usage-antigravity.orig"
fi
install -m 0755 "$COLLECTOR" "$BIN_DIR/omarchy-agent-usage-antigravity"
echo "collector: installed $BIN_DIR/omarchy-agent-usage-antigravity"

echo "zamecki.antigravity: install complete"
echo "Enable with: omarchy plugin enable zamecki.antigravity"