#!/bin/bash

# zamecki.antigravity uninstaller.
#
# Undoes everything done by install.sh:
# - Removes the Defaults -> Agent menu entry
# - Removes the CLI shims from the plugin's shim directory
# - Removes the PATH blocks that put those shims first
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
MENU_LINE_RE="^[[:space:]]*\"${MENU_ID//./\\.}\"[[:space:]]*:"
SHIM_DIR="$HOME/.local/share/zamecki.antigravity/bin"
LEGACY_BIN_DIR="$HOME/.local/bin"
SHIMS=(omarchy-default-agent omarchy-agent omarchy-agent-usage-update)
MARKER='# zamecki.antigravity shim'
STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/agents/usage/antigravity.json"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/agent-usage"
DEFAULT_AGENT_FILE="$HOME/.config/omarchy/defaults/agent"
BASH_RC="$HOME/.bashrc"
HYPR_LUA="$HOME/.config/hypr/hyprland.lua"
BASH_BLOCK_START='# >>> zamecki.antigravity >>>'
BASH_BLOCK_END='# <<< zamecki.antigravity <<<'
HYPR_BLOCK_START='-- >>> zamecki.antigravity >>>'
HYPR_BLOCK_END='-- <<< zamecki.antigravity <<<'

# --- Menu row ---------------------------------------------------------------
# install.sh writes the row as one line, so dropping that line is the whole
# undo. A trailing comma it may leave behind is accepted by the menu's JSONC
# reader, and nothing else in the file is touched.
if [[ -f $MENU_FILE ]] && grep -q "$MENU_LINE_RE" "$MENU_FILE"; then
  menu=$(realpath "$MENU_FILE")
  tmp=$(mktemp "$menu.XXXXXX")
  grep -v "$MENU_LINE_RE" "$menu" >"$tmp" || true
  chmod --reference="$menu" "$tmp"
  mv -f "$tmp" "$menu"
  echo "menu: removed $MENU_ID"
fi

# --- Shims ------------------------------------------------------------------
# Only remove files carrying our marker, so a command someone else put on PATH
# under the same name survives.
for dir in "$SHIM_DIR" "$LEGACY_BIN_DIR"; do
  for name in "${SHIMS[@]}"; do
    dst="$dir/$name"
    [[ -f $dst && ! -L $dst ]] || continue
    if grep -qFx "$MARKER" "$dst" 2>/dev/null; then
      rm -f "$dst"
      echo "shim: removed $dst"
    fi
  done
done
rmdir "$SHIM_DIR" 2>/dev/null || true
rmdir "$(dirname "$SHIM_DIR")" 2>/dev/null || true

# --- PATH -------------------------------------------------------------------
# Drop the marked blocks only; the rest of the user's files is left untouched.
# A dotfiles symlink is followed so the target keeps its link.
remove_block() {
  local file=$1 start=$2 end=$3 tmp
  [[ -f $file ]] || return 0
  grep -qF -- "$start" "$file" || return 0
  file=$(realpath "$file")
  tmp=$(mktemp "$file.XXXXXX")
  awk -v start="$start" -v end="$end" '
    $0 == start { skip = 1; next }
    skip && $0 == end { skip = 0; next }
    !skip { print }
  ' "$file" >"$tmp"
  chmod --reference="$file" "$tmp"
  mv -f "$tmp" "$file"
  echo "path: removed shim directory from $file"
}

remove_block "$BASH_RC" "$BASH_BLOCK_START" "$BASH_BLOCK_END"
remove_block "$HYPR_LUA" "$HYPR_BLOCK_START" "$HYPR_BLOCK_END"

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

# --- Default Agent ----------------------------------------------------------
# Nothing can launch antigravity once the shims are gone, so leaving it selected
# would only earn an "Unsupported default agent" from the packaged omarchy-agent.
if [[ -f $DEFAULT_AGENT_FILE ]] && [[ "$(< "$DEFAULT_AGENT_FILE")" == "antigravity" ]]; then
  rm -f "$DEFAULT_AGENT_FILE"
  echo "defaults: cleared antigravity default agent setting"
fi

echo "zamecki.antigravity: uninstall complete"
