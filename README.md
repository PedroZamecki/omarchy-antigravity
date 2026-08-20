# zamecki.antigravity

Adds the Antigravity CLI (`agy`, Google's Gemini Code Assist terminal agent) as an
Omarchy agent option, alongside the agents shipped by `omarchy.agents`.

## What it does

- **Agents panel tab** — a service writes a usage record to
  `~/.local/state/omarchy/agents/usage/antigravity.json` every 15 minutes (and at
  shell start). The existing agents panel picks it up automatically and shows a
  new "Antigravity" subscription card.
- **Defaults → Agent menu entry** — a new `Antigravity` row under
  *Defaults → Agent* in the omarchy menu. Selecting it installs `agy` on demand
  via mise (`aqua:google-antigravity/antigravity-cli`) and launches the TUI.
- **Agent launch** — the bar's agent icon / `omarchy agent` flow launches `agy`
  when Antigravity is the default agent (with `--dangerously-skip-permissions`,
  or `agy -p "<prompt>"` for a one-shot prompt).

## How the subscription record is built

The collector (`bin/omarchy-agent-usage-antigravity`) is a dependency-free
Python 3 script. It builds the same record schema as the other agent collectors:

| Field | Source |
| --- | --- |
| `tierLabel` | Live call to `cloudcode-pa.googleapis.com/v1internal:loadCodeAssist` with OAuth token. Returns the allowed tier name, e.g. "Gemini Code Assist". |
| `limits` | Live call to `cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota` returning per-model quota buckets, usage percentages, and reset timestamps (e.g. Gemini 2.5 Pro, Flash, etc.). |
| `todayTotalTokens` / `todayTokensByModel` / `modelUsage` | Scanned from local conversation transcripts (`~/.gemini/antigravity-cli/brain/*/logs/transcript.jsonl`), tracking model switches and token counts per model. |
| `todayPrompts` / `totalPrompts` | The CLI's prompt history and transcript records. |
| `todaySessions` / `totalSessions` / `activeDays` / `activeDates` / `recentDays` | Brain transcripts combined with `conversation_summaries.db` (`~/.gemini/antigravity-cli/`) for 7-day token and prompt activity charts. |
| `authHelpText` | "Run `agy` to sign in to Antigravity." when signed out. |

When the stored access token expires, the collector automatically refreshes it
against Google's OAuth2 token endpoint using the stored refresh token.

**Fallback tier:** if the user is signed out or the live call fails, the tier
label falls back to the declared plan in
`~/.config/omarchy/agents/antigravity.json`:

```json
{ "tierLabel": "Gemini Code Assist" }
```

When it is absent, the neutral label `Antigravity` is used.

## Install

The plugin must be enabled so its service runs. The menu row and the wrappers are
installed by `install.sh`:

```sh
~/.config/omarchy/plugins/zamecki.antigravity/install.sh
omarchy plugin enable zamecki.antigravity
```

`install.sh` is idempotent and safe to re-run after `omarchy refresh`. It:

1. Installs `fonts/omarchy-antigravity.ttf` (custom glyph built from the Antigravity SVG mark) into `~/.local/share/fonts/`.
2. Adds or updates the `setup.default.agent.antigravity` row in
   `~/.config/omarchy/extensions/omarchy-menu.jsonc` (using the custom glyph and `"iconFont": "omarchy-antigravity"`).
3. Installs `omarchy-default-agent` and `omarchy-agent` wrappers into
   `~/.local/bin/` so the menu rows, bar launch, and keybinding resolve to the
   Antigravity-aware versions (backing up existing files to `*.orig`).
4. Installs the usage collector into `~/.local/bin/` (the service invokes it by
   bare name, like the packaged collectors).

## Known limitations

- The `omarchy default agent <name>` and `omarchy agent` CLI groups are resolved
  by Omarchy's dispatcher from its own `/usr/share/omarchy/bin` directory only,
  so they keep using the packaged scripts that do not know `antigravity`. The
  interactive paths (menu selection, menu checked-state, bar launch, keybinding)
  go through the shell and use the wrappers, so they work. Running
  `omarchy agent` from a terminal with Antigravity as the default prints a clear
  message and exits.
- Token refresh is handled by the CLI itself; the collector never refreshes
  tokens. If the keyring entry is missing or expired, the record reports the
  signed-out state until `agy` is run again.

## Uninstall

To remove all installed system extensions, font, wrappers, and configuration:

```sh
~/.config/omarchy/plugins/zamecki.antigravity/uninstall.sh
```

To also delete the plugin folder itself:

```sh
rm -rf ~/.config/omarchy/plugins/zamecki.antigravity
```