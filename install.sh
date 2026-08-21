#!/bin/bash

# zamecki.antigravity installer.
#
# Adds the Antigravity entry to the Defaults -> Agent menu and installs the
# shims that route omarchy-default-agent / omarchy-agent / omarchy-agent-usage-update
# into this plugin's wrappers.
# Idempotent: safe to run again after `omarchy refresh`.

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MENU_FILE="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
MENU_ID="setup.default.agent.antigravity"
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

# --- Legacy cleanup ---------------------------------------------------------
# Older versions copied the collector onto PATH and left .orig backups beside
# every file they replaced. The collector now runs from the plugin folder and
# nothing is backed up any more, so sweep both away.
# Every name in the list below is one only this plugin ever creates, so an
# Antigravity mention in the header is enough to confirm it is ours and not a
# stranger's file that happens to share the name.
sweep_legacy() {
  local dst="$1"
  [[ -f $dst && ! -L $dst ]] || return 0
  head -n 5 "$dst" | grep -qiE 'zamecki\.antigravity|antigravity' || return 0
  rm -f "$dst"
  echo "legacy: removed $dst"
}

for name in omarchy-agent-usage-antigravity \
  omarchy-default-agent.orig omarchy-agent.orig \
  omarchy-agent-usage-update.orig omarchy-agent-usage-antigravity.orig; do
  sweep_legacy "$BIN_DIR/$name"
done

# The icon font is now loaded at runtime by Service.qml instead of being
# installed system-wide, so drop a copy left by an older install.sh.
LEGACY_FONT="$HOME/.local/share/fonts/omarchy-antigravity.ttf"
if [[ -f $LEGACY_FONT ]]; then
  rm -f "$LEGACY_FONT"
  command -v fc-cache >/dev/null 2>&1 && fc-cache -f "$(dirname "$LEGACY_FONT")" >/dev/null 2>&1
  echo "legacy: removed $LEGACY_FONT"
fi

# --- Menu row ---------------------------------------------------------------
# The `when:` guard means a leftover row renders nothing once the plugin folder
# is gone, so a stale key in the user's menu extension stays inert instead of
# offering an agent that can no longer be launched.
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
    '"when":"[[ -d \\"$HOME/.config/omarchy/plugins/zamecki.antigravity\\" ]]",'
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
exec /usr/share/omarchy/bin/$name "\$@"
SHIM
  echo "shim: installed $BIN_DIR/$name"
done

echo "zamecki.antigravity: install complete"
echo "Enable with: omarchy plugin enable zamecki.antigravity"
