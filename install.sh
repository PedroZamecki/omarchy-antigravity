#!/bin/bash

# agy-integration installer.
#
# Adds the Antigravity entry to the Defaults -> Agent menu, installs the shims
# that route omarchy-default-agent / omarchy-agent / omarchy-agent-usage-update
# into this plugin's wrappers, and makes sure those shims resolve before
# Omarchy's own bin directories on PATH.
# Idempotent: safe to run again after `omarchy refresh`.

set -euo pipefail

PLUGIN_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
MENU_FILE="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
MENU_ID="setup.default.agent.antigravity"
MENU_LINE_RE="^[[:space:]]*\"${MENU_ID//./\\.}\"[[:space:]]*:"
# A dedicated directory rather than ~/.local/bin. Current Omarchy puts
# /usr/share/omarchy/bin (and /usr/bin) ahead of ~/.local/bin, so shims there
# never win; only these three names need the earlier precedence.
SHIM_DIR="$HOME/.local/share/agy-integration/bin"
LEGACY_BIN_DIR="$HOME/.local/bin"
SHIMS=(omarchy-default-agent omarchy-agent omarchy-agent-usage-update)
MARKER='# agy-integration shim'
# Matches both the shims below and the full wrapper copies older versions
# installed, so an upgrade replaces its own files instead of refusing them.
OWNED_RE='^# agy-integration'
BASH_RC="$HOME/.bashrc"
HYPR_LUA="$HOME/.config/hypr/hyprland.lua"
BASH_BLOCK_START='# >>> agy-integration >>>'
BASH_BLOCK_END='# <<< agy-integration <<<'
HYPR_BLOCK_START='-- >>> agy-integration >>>'
HYPR_BLOCK_END='-- <<< agy-integration <<<'

missing=()
for dep in bash jq python3 mise; do
  command -v "$dep" >/dev/null 2>&1 || missing+=("$dep")
done
if ((${#missing[@]} > 0)); then
  echo "deps: missing ${missing[*]} (Antigravity needs bash, jq, python3 and mise)" >&2
fi

mkdir -p "$(dirname "$MENU_FILE")" "$SHIM_DIR"

owned_by_plugin() {
  [[ -f $1 && ! -L $1 ]] && head -n 5 "$1" | grep -qE "$OWNED_RE"
}

# --- Menu row ---------------------------------------------------------------
# The `when:` guard means a leftover row renders nothing once the plugin is
# disabled or gone, so a stale key in the user's menu extension stays inert instead of
# offering an agent that can no longer be launched.
# The row always goes right after the opening brace with a trailing comma, which
# the menu's JSONC reader accepts, so no other line of the file is ever touched.
# The action and checked expression call the wrapper by absolute path: the menu
# works even in a shell whose PATH has not been updated yet.
WRAPPER="$PLUGIN_DIR/wrappers/omarchy-default-agent"
ROW=$(cat <<ROW_EOF
  "$MENU_ID": {"icon":"\ue908","iconFont":"omarchy-antigravity","label":"Antigravity","when":"omarchy plugin list --json | jq -e '.[] | select(.id == \"agy-integration\" and .enabled)' >/dev/null","checked":"[[ \"\$(bash \"$WRAPPER\")\" == \"antigravity\" ]]","action":"bash \"$WRAPPER\" antigravity"},
ROW_EOF
)

# A dotfiles symlink is followed, so the edit lands on its target and the link
# itself survives.
menu=$(realpath "$MENU_FILE")
[[ -f $menu ]] || printf '{\n}\n' >"$menu"
tmp=$(mktemp "$menu.XXXXXX")
if ! { grep -v "$MENU_LINE_RE" "$menu" || true; } | ROW=$ROW awk '
  !done && /^[[:space:]]*\{/ {
    i = index($0, "{")
    print substr($0, 1, i)
    print ENVIRON["ROW"]
    if (substr($0, i + 1) != "") print substr($0, i + 1)
    done = 1
    next
  }
  { print }
  END { exit !done }
' >"$tmp"; then
  rm -f "$tmp"
  echo "menu: refusing to edit $MENU_FILE (no opening '{' found)" >&2
  exit 1
fi
if cmp -s "$tmp" "$menu"; then
  rm -f "$tmp"
else
  chmod --reference="$menu" "$tmp"
  mv -f "$tmp" "$menu"
  echo "menu: wrote $MENU_ID"
fi

# --- PATH -------------------------------------------------------------------
# The interactive menu and the agents panel both run commands through
# `bash -lc`, which reads this user's bashrc. Hyprland itself dispatches the
# keybinding from its own environment, so it needs the same line in its config.
# Both blocks are marked, idempotent and removed by uninstall.sh.
insert_bash_block() {
  local file=$BASH_RC tmp
  [[ -f $file ]] && grep -qF "$BASH_BLOCK_START" "$file" && return 0
  [[ -e $file ]] && file=$(realpath "$file")
  mkdir -p "$(dirname "$file")"
  [[ -f $file ]] || : >"$file"
  tmp=$(mktemp "$file.XXXXXX")
  {
    printf '%s\n' "$BASH_BLOCK_START"
    printf '%s\n' "# Put the plugin shims ahead of Omarchy's bin directories, which the"
    printf '%s\n' '# desktop session and env-bootstrap place before ~/.local/bin.'
    printf '%s\n' 'case ":$PATH:" in'
    printf '%s\n' "  *\":$SHIM_DIR:\"*) ;;"
    printf '%s\n' "  *) PATH=\"$SHIM_DIR\${PATH:+:\$PATH}\" ;;"
    printf '%s\n' 'esac'
    printf '%s\n' 'export PATH'
    printf '%s\n' "$BASH_BLOCK_END"
    cat "$file"
  } >"$tmp"
  chmod --reference="$file" "$tmp"
  mv -f "$tmp" "$file"
  echo "path: added shim directory to $BASH_RC"
}

insert_hypr_block() {
  local file=$HYPR_LUA tmp
  [[ -f $file ]] || return 0
  grep -qF -- "$HYPR_BLOCK_START" "$file" && return 0
  file=$(realpath "$file")
  tmp=$(mktemp "$file.XXXXXX")
  cat "$file" >"$tmp"
  {
    printf '\n%s\n' "$HYPR_BLOCK_START"
    printf '%s\n' '-- Let the agent keybinding resolve the plugin shims first.'
    printf '%s\n' "hl.env(\"PATH\", \"$SHIM_DIR:\" .. (os.getenv(\"PATH\") or \"\"))"
    printf '%s\n' "$HYPR_BLOCK_END"
  } >>"$tmp"
  chmod --reference="$file" "$tmp"
  mv -f "$tmp" "$file"
  echo "path: added shim directory to $HYPR_LUA (log out and back in, or run 'hyprctl reload', for the agent keybinding)"
}

insert_bash_block
insert_hypr_block

# --- Shims ------------------------------------------------------------------
# Only these few lines ever land on disk; the real wrapper logic stays in the
# plugin folder, so `omarchy plugin update` takes effect without reinstalling.
# Omarchy has no disable or uninstall hook (disabling reloads the whole shell, so
# a QML teardown handler never gets to run), so the shims are the hook: when the
# plugin folder is gone, or `omarchy plugin list` reports it disabled, a shim
# undoes the install and hands the call to the packaged command. An unknown state
# (the lookup failing) keeps a live install working rather than tearing it down.
write_shim() {
  local dst="$1"

  # A symlink here would let install write straight through to its target, and a
  # file we did not create is someone else's: refuse both rather than clobber.
  if [[ -L $dst ]]; then
    echo "shim: refusing to write $dst (it is a symlink)" >&2
    return 1
  fi
  if [[ -e $dst ]] && ! owned_by_plugin "$dst"; then
    echo "shim: refusing to overwrite $dst (not created by this plugin)" >&2
    return 1
  fi

  # Write to a sibling temp file and rename over the destination: atomic, and it
  # replaces a symlink rather than following one.
  local tmp
  tmp=$(mktemp "$dst.XXXXXX") || return 1
  cat >"$tmp" && chmod 0755 "$tmp" && mv -f "$tmp" "$dst"
}

# Older releases wrote the shims into ~/.local/bin, where Omarchy's own bin
# directories shadow them. Remove those copies so upgrades do not leave two
# generations behind.
for name in "${SHIMS[@]}"; do
  legacy="$LEGACY_BIN_DIR/$name"
  if [[ -f $legacy && ! -L $legacy ]] && grep -qFx "$MARKER" "$legacy" 2>/dev/null; then
    rm -f "$legacy"
    echo "shim: removed legacy $legacy"
  fi
done

for name in "${SHIMS[@]}"; do
  # The menu's checked: expressions ask omarchy-default-agent for the current
  # agent once per row. With no arguments the wrapper and the packaged command
  # answer identically, so that hot path skips the enabled lookup.
  query=""
  [[ $name == omarchy-default-agent ]] && query='(($#)) || exec "${OMARCHY_PATH:-/usr/share/omarchy}/bin/omarchy-default-agent"'
  # Keyed on the plugin folder, not on the wrapper being executable: a checkout
  # that drops the exec bit must not read as "plugin removed" and self-destruct.
  write_shim "$SHIM_DIR/$name" <<SHIM
#!/bin/bash
$MARKER
$query
plugin="$PLUGIN_DIR"
# The plugin folder can be deleted before a shim runs (omarchy plugin remove),
# so the fallback removes the marked PATH blocks itself instead of relying on
# uninstall.sh, which is gone at that point.
strip_block() {
  local f=\$1 s=\$2 e=\$3 t
  [[ -f \$f ]] || return 0
  grep -qF -- "\$s" "\$f" || return 0
  f=\$(realpath "\$f")
  t=\$(mktemp "\$f.XXXXXX") || return 0
  awk -v s="\$s" -v e="\$e" '\$0 == s { skip = 1; next } skip && \$0 == e { skip = 0; next } !skip { print }' "\$f" >"\$t" &&
    chmod --reference="\$f" "\$t" && mv -f "\$t" "\$f"
}
if [[ ! -d \$plugin || \$(omarchy plugin list --json 2>/dev/null | jq -r '.[] | select(.id == "agy-integration") | .enabled') == false ]]; then
  if [[ -f \$plugin/uninstall.sh ]]; then
    bash "\$plugin/uninstall.sh" >/dev/null
  else
    for f in ${SHIMS[*]}; do grep -qFx "$MARKER" "\${0%/*}/\$f" 2>/dev/null && rm -f "\${0%/*}/\$f"; done
    rmdir "\${0%/*}" 2>/dev/null || true
    rm -f "\${XDG_STATE_HOME:-\$HOME/.local/state}/omarchy/agents/usage/antigravity.json"
    [[ \$(cat "\$HOME/.config/omarchy/defaults/agent" 2>/dev/null) == antigravity ]] && rm -f "\$HOME/.config/omarchy/defaults/agent"
    strip_block "\$HOME/.bashrc" '# >>> agy-integration >>>' '# <<< agy-integration <<<'
    strip_block "\$HOME/.config/hypr/hyprland.lua" '-- >>> agy-integration >>>' '-- <<< agy-integration <<<'
  fi
  exec "\${OMARCHY_PATH:-/usr/share/omarchy}/bin/$name" "\$@"
fi
exec bash "\$plugin/wrappers/$name" "\$@"
SHIM
  echo "shim: installed $SHIM_DIR/$name"
done

echo "agy-integration: install complete"
