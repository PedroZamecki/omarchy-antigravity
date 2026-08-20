#!/bin/bash

# zamecki.antigravity uninstaller.
#
# Undoes everything done by install.sh:
# - Disables the plugin in Omarchy
# - Removes the Defaults -> Agent menu entry
# - Restores or removes CLI wrappers and usage collector from ~/.local/bin
# - Removes the icon font from ~/.local/share/fonts
# - Cleans up usage state and cache files
#
# Idempotent: safe to run multiple times.

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MENU_FILE="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
MENU_ID="setup.default.agent.antigravity"
BIN_DIR="$HOME/.local/bin"
WRAPPERS=("omarchy-default-agent" "omarchy-agent")
COLLECTOR_NAME="omarchy-agent-usage-antigravity"
FONT_PATH="$HOME/.local/share/fonts/omarchy-antigravity.ttf"
STATE_FILE="$HOME/.local/state/omarchy/agents/usage/antigravity.json"
CACHE_FILE="$HOME/.cache/omarchy/agent-usage/antigravity-tier-cache.json"
DEFAULT_AGENT_FILE="$HOME/.config/omarchy/defaults/agent"

# --- Disable plugin ---------------------------------------------------------
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable zamecki.antigravity 2>/dev/null || true
  echo "plugin: disabled zamecki.antigravity"
fi

# --- Menu row ---------------------------------------------------------------
if [[ -f $MENU_FILE ]]; then
  python3 - "$MENU_FILE" "$MENU_ID" <<'PYEOF'
import re, sys

path, key = sys.argv[1], sys.argv[2]
try:
    with open(path) as fh:
        content = fh.read()
except FileNotFoundError:
    sys.exit(0)

if '"' + key + '"' not in content:
    sys.exit(0)

pattern1 = r',\s*\n([ \t]*"' + re.escape(key) + r'"\s*:.*?\n\s*\})'
content = re.sub(pattern1, r'\n\1', content)
pattern2 = r'^[ \t]*"' + re.escape(key) + r'"\s*:.*?(?:,\s*|\s*)$(?:\n)?'
content = re.sub(pattern2, '', content, flags=re.MULTILINE)
content = re.sub(r',\s*(\n\s*\})', r'\1', content)

with open(path, "w") as fh:
    fh.write(content)
print("menu: removed " + key)
PYEOF
fi

# --- Wrappers ---------------------------------------------------------------
for name in "${WRAPPERS[@]}"; do
  dst="$BIN_DIR/$name"
  if [[ -f "$dst.orig" ]]; then
    mv "$dst.orig" "$dst"
    echo "wrapper: restored $dst from .orig"
  elif [[ -f "$dst" ]]; then
    rm -f "$dst"
    echo "wrapper: removed $dst"
  fi
done

# --- Collector --------------------------------------------------------------
collector_dst="$BIN_DIR/$COLLECTOR_NAME"
if [[ -f "$collector_dst.orig" ]]; then
  mv "$collector_dst.orig" "$collector_dst"
  echo "collector: restored $collector_dst from .orig"
elif [[ -f "$collector_dst" ]]; then
  rm -f "$collector_dst"
  echo "collector: removed $collector_dst"
fi

# --- Icon Font --------------------------------------------------------------
if [[ -f $FONT_PATH ]]; then
  rm -f "$FONT_PATH"
  echo "font: removed $FONT_PATH"
  if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f "$(dirname "$FONT_PATH")" >/dev/null 2>&1 || true
  fi
fi

# --- State & Cache ----------------------------------------------------------
if [[ -f $STATE_FILE ]]; then
  rm -f "$STATE_FILE"
  echo "state: removed $STATE_FILE"
fi

if [[ -f $CACHE_FILE ]]; then
  rm -f "$CACHE_FILE"
  echo "cache: removed $CACHE_FILE"
fi

# --- Default Agent ----------------------------------------------------------
if [[ -f $DEFAULT_AGENT_FILE ]] && [[ "$(< "$DEFAULT_AGENT_FILE")" == "antigravity" ]]; then
  rm -f "$DEFAULT_AGENT_FILE"
  echo "defaults: cleared antigravity default agent setting"
fi

echo "zamecki.antigravity: uninstall complete"
