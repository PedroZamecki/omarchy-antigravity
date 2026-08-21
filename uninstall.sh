#!/bin/bash

# zamecki.antigravity uninstaller.
#
# Undoes everything done by install.sh:
# - Removes the Defaults -> Agent menu entry
# - Removes the CLI shims from ~/.local/bin
# - Cleans up usage state and cache files
#
# Runs automatically from Service.qml when the plugin is disabled or removed;
# also safe to run by hand. Idempotent.
#
# It deliberately does not disable the plugin: it is normally invoked *because*
# the plugin was just disabled.

set -euo pipefail

MENU_FILE="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
MENU_ID="setup.default.agent.antigravity"
BIN_DIR="$HOME/.local/bin"
SHIMS=(omarchy-default-agent omarchy-agent omarchy-agent-usage-update)
MARKER='# zamecki.antigravity shim'
STATE_FILE="$HOME/.local/state/omarchy/agents/usage/antigravity.json"
CACHE_DIR="$HOME/.cache/omarchy/agent-usage"
DEFAULT_AGENT_FILE="$HOME/.config/omarchy/defaults/agent"
LEGACY_FONT="$HOME/.local/share/fonts/omarchy-antigravity.ttf"

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

# --- Shims ------------------------------------------------------------------
# Only remove files carrying our marker, so a command someone else put on PATH
# under the same name survives.
for name in "${SHIMS[@]}"; do
  dst="$BIN_DIR/$name"
  [[ -f $dst && ! -L $dst ]] || continue
  if grep -qFx "$MARKER" "$dst" 2>/dev/null; then
    rm -f "$dst"
    echo "shim: removed $dst"
  fi
done

# --- State & Cache ----------------------------------------------------------
if [[ -f $STATE_FILE ]]; then
  rm -f "$STATE_FILE"
  echo "state: removed $STATE_FILE"
fi

# The collector's cache filenames include a hash suffix (antigravity-limits.json,
# antigravity-scan-<hash>.json/.lock), so glob rather than naming them one by one.
shopt -s nullglob
cache_files=("$CACHE_DIR"/antigravity-*)
shopt -u nullglob
if ((${#cache_files[@]} > 0)); then
  rm -f "${cache_files[@]}"
  echo "cache: removed ${#cache_files[@]} file(s) from $CACHE_DIR"
fi

# --- Legacy font --------------------------------------------------------------
# Older versions installed the icon font system-wide; current Service.qml loads
# it at runtime instead. Clean it up here too in case uninstall runs before
# install.sh ever gets a chance to (its own legacy sweep covers the same file).
if [[ -f $LEGACY_FONT ]]; then
  rm -f "$LEGACY_FONT"
  command -v fc-cache >/dev/null 2>&1 && fc-cache -f "$(dirname "$LEGACY_FONT")" >/dev/null 2>&1
  echo "legacy: removed $LEGACY_FONT"
fi

# --- Default Agent ----------------------------------------------------------
# Nothing can launch antigravity once the shims are gone, so leaving it selected
# would only earn an "Unsupported default agent" from the packaged omarchy-agent.
if [[ -f $DEFAULT_AGENT_FILE ]] && [[ "$(< "$DEFAULT_AGENT_FILE")" == "antigravity" ]]; then
  rm -f "$DEFAULT_AGENT_FILE"
  echo "defaults: cleared antigravity default agent setting"
fi

echo "zamecki.antigravity: uninstall complete"
