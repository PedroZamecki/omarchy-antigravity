#!/bin/bash

# zamecki.antigravity installer.
#
# Adds the Antigravity entry to the Defaults -> Agent menu and installs the
# shims that route omarchy-default-agent / omarchy-agent / omarchy-agent-usage-update
# into this plugin's wrappers.
# Idempotent: safe to run again after `omarchy refresh`.

set -euo pipefail

MENU_FILE="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
MENU_ID="setup.default.agent.antigravity"
MENU_LINE_RE="^[[:space:]]*\"${MENU_ID//./\\.}\"[[:space:]]*:"
BIN_DIR="$HOME/.local/bin"
SHIMS=(omarchy-default-agent omarchy-agent omarchy-agent-usage-update)
MARKER='# zamecki.antigravity shim'
# Matches both the shims below and the full wrapper copies older versions
# installed, so an upgrade replaces its own files instead of refusing them.
OWNED_RE='^# zamecki\.antigravity'

mkdir -p "$(dirname "$MENU_FILE")" "$BIN_DIR"

owned_by_plugin() {
  [[ -f $1 && ! -L $1 ]] && head -n 5 "$1" | grep -qE "$OWNED_RE"
}

# --- Menu row ---------------------------------------------------------------
# The `when:` guard means a leftover row renders nothing once the plugin folder
# is gone, so a stale key in the user's menu extension stays inert instead of
# offering an agent that can no longer be launched.
# The row always goes right after the opening brace with a trailing comma, which
# the menu's JSONC reader accepts, so no other line of the file is ever touched.
ROW='  "'"$MENU_ID"'": {"icon":"\ue908","iconFont":"omarchy-antigravity","label":"Antigravity","when":"[[ -d \"$HOME/.config/omarchy/plugins/zamecki.antigravity\" ]]","checked":"[[ \"$(omarchy-default-agent)\" == \"antigravity\" ]]","action":"omarchy-default-agent antigravity"},'

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

# --- Shims ------------------------------------------------------------------
# Only these six lines ever land in ~/.local/bin; the real wrapper logic stays in
# the plugin folder, so `omarchy plugin update` takes effect without reinstalling.
# When the plugin folder is gone the shim removes itself, clears a default agent
# nothing can launch any more, and hands the call to the packaged command -- so
# every removal path cleans itself up on first use, hook or no hook.
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

for name in "${SHIMS[@]}"; do
  # Keyed on the plugin folder, not on the wrapper being executable: a checkout
  # that drops the exec bit must not read as "plugin removed" and self-destruct.
  write_shim "$BIN_DIR/$name" <<SHIM
#!/bin/bash
$MARKER
plugin="\$HOME/.config/omarchy/plugins/zamecki.antigravity"
[[ -d \$plugin ]] && exec bash "\$plugin/wrappers/$name" "\$@"
rm -f "\$0"
[[ \$(cat "\$HOME/.config/omarchy/defaults/agent" 2>/dev/null) == antigravity ]] && rm -f "\$HOME/.config/omarchy/defaults/agent"
exec "\${OMARCHY_PATH:-/usr/share/omarchy}/bin/$name" "\$@"
SHIM
  echo "shim: installed $BIN_DIR/$name"
done

echo "zamecki.antigravity: install complete"
