# Agents

This document collects findings from agents working in this Plasma Widgets repository and defines conventions for sharing information.

## Plasma 6 Requirement

Finding: All widgets currently target KDE Plasma 6.

* `agenda/metadata.json` → `X-Plasma-API-Minimum-Version: 6.0`
* `antigravity-usage/metadata.json` → `X-Plasma-API-Minimum-Version: 6.0`
* `claude-usage/metadata.json` → `X-Plasma-API-Minimum-Version: 6.0`
* `clickup-tasks/metadata.json` → `X-Plasma-API-Minimum-Version: 6.0`
* `compact-media-player/metadata.json` → `X-Plasma-API-Minimum-Version: 6.0`
* `freellmapi-usage/metadata.json` → `X-Plasma-API-Minimum-Version: 6.0`
* `herdr-status/metadata.json` → `X-Plasma-API-Minimum-Version: 6.0`

Implication: Ensure built widgets will work on Plasma 6. Do not use Plasma 5 APIs, Qt5 imports, or Plasma Shell 5 components. Build/test against Qt 6 / Kirigami 2 / Plasma 6.

## Widget Findings

### freellmapi-usage
* Python fetcher `contents/code/freellmapi.py`.
* Config via `~/.config/freellmapi-usage/config.json` with `session_token`.
* Reads REST API `/api/analytics/*` and read-only SQLite `PRAGMA query_only`.
* Detects model-catalog changes via `settings.catalog_applied_version` comparison, caches to `~/.cache/freellmapi-usage/catalog_version.json`.
* Metadata declares `X-Plasma-MainScript: ui/main.qml` and default size 520×520.

### agenda
* Google Calendar ICS feeds. `contents/code/feeds.example.js`, `feeds.js`, `ics.js`.
* UI in `contents/ui/main.qml`. Catppuccin Mocha theme.
* Category Date and Time.

### claude-usage
* Tracks Claude Code session/weekly usage.
* UI components: `TypingCat.qml`, `UsageBar.qml`, `UsageRing.qml`, `main.qml`.
* Reads `~/.claude/plasma-usage-status.json`, written by the statusLine hook in `hook/` (install with `hook/setup-claude-usage-hook.py`). Own README exists.
* Category System Information.

### clickup-tasks
* Python fetcher `contents/code/clickup.py`; QML only renders its JSON.
* Config lives at `~/.config/clickup-tasks/config.json` (token). The repo's
  `config.json` is gitignored — never commit it; `config.example.json` is the template.
* Own README exists.
* Test the data path without Plasma: `python3 contents/code/clickup.py` (JSON on
  stdout, logs on stderr). Check counts against an independent pass over the raw API
  before claiming numbers are right.
* ClickUp API quirks this widget depends on:
  * `include_closed=false` drops only *closed*-type statuses. "done"/"completed"
    statuses are type `done` and still come back — filter on `status.type`.
  * Date-only due dates are stored as 04:00 local time. Compare calendar days,
    not `due < now`, or tasks due today show as overdue from 4am.
  * `GET /team/{id}/task` pages at 100. Fetch every page for counts; `max_tasks`
    caps only the returned list.
* Behaviour the user asked for (2026-10-14): show only active tasks (start date ≤
  today, or no start date and due ≤ today); exclude done/closed; buckets are just
  overdue/open; sort by priority (urgent→low→none), then due date (start date if no
  due); left bar coloured by priority (urgent red, high yellow, normal purple, low
  grey, none black).

### antigravity-usage
* Tracks antigravity-cli weekly quota (`gemini-weekly` ring, `3p-weekly` bar) and context usage.
* Reads `~/.gemini/antigravity-cli/plasma-agy-status.json`, written by the statusLine hook in `hook/` (install with `hook/setup-antigravity-usage-hook.py`). Own README exists.
* UI components: `TypingDog.qml`, `UsageBar.qml`, `UsageRing.qml`, `main.qml`.
* Id `io.github.holty07.antigravityusage`.

### herdr-status
* Live herdr agent states; polls the `herdr` binary. v2.0 (2026-11-20).
* Panel: running (working, blue) / waiting (blocked, yellow) / idle dots. The idle
  dot merges herdr's idle, done and unknown states. Desktop (Planar form factor):
  full agent list.
* Settings (`contents/config/main.xml`): herdr binary path, poll interval, hide idle
  (default `false`), highlight when blocked.
* `herdrBinary` defaults to plain `herdr`. Plasma's session PATH includes
  `~/.local/bin`, so don't hardcode a home path (public repo).
* Id `io.github.holty07.herdrstatus`. MIT licensed.

### compact-media-player
* MPRIS now-playing controller with a cava visualiser. Moved into the repo
  2026-11-20 from a local-only install; Id renamed from
  `org.kde.plasma.compactmediaplayer` to `io.github.holty07.compactmediaplayer`.
* Uses `org.kde.plasma.private.mpris` (`Mpris2Model`). Plasma's model always jumps
  to the most recent player, so `pinPlayer` / `pinnedPlayer` steer `currentIndex`
  back to one player, matched on desktop entry first, then identity.
* The user's player is limusic. It registers `org.mpris.MediaPlayer2.limusic` with
  identity `Limusic` and no `DesktopEntry`, so the pin is `Limusic`.
* Visualiser: `support/` holds `cava-plasmoid-bridge` (keeps the newest cava frame at
  `$XDG_RUNTIME_DIR/cava-plasmoid.raw`), its systemd user unit and the cava config.
  `CavaSource.qml` reads the frame. Install steps are in the widget README.

## This Machine (Findings 2026-10-14)

* CachyOS, **plasmashell 6.7.5** (Qt 6), Wayland session, screen at 2x scale.
* Widgets are installed in `~/.local/share/plasma/plasmoids/` (checked 2026-11-20).
  `agenda`, `antigravity-usage`, `clickup-tasks`, `compact-media-player`,
  `freellmapi-usage` and `herdr-status` are **symlinks** into this repo, so edits are
  live after a shell restart. Do not run `kpackagetool6 -u` on those (it would
  replace the symlink with a copy).
* `claude-usage` is a **copied** install (matches the repo as of 2026-11-20): refresh
  it with `kpackagetool6 -t Plasma/Applet -u <widget dir>`.
* Renaming a widget Id: stop `plasma-plasmashell.service`, change the `plugin=` line
  in `~/.config/plasma-org.kde.plasma.desktop-appletsrc`, swap the install, then
  start the service. Editing appletsrc while Plasma runs gets overwritten, and a
  changed Id with no appletsrc update drops the widget off the panel.
* To change one running widget's config without a restart, use the scripting API:
  `qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '…'`
  with `widget.currentConfigGroup = ["General"]; widget.writeConfig(key, value)`.
* The repo path contains a space (`Plasma Widgets`). Quote paths everywhere,
  including the commands QML hands to the `executable` DataSource (it runs them
  through a shell).
* `executable` DataSource commands inherit the session environment, so `python3`
  must resolve in the Plasma session, not just your terminal.

## Restarting plasmashell

plasmashell should run under its systemd user unit, `plasma-plasmashell.service`.
Then a restart is a single synchronous command: no background shell, no orphaned
process tied to your tool session, and logs go to the journal.

```sh
systemctl --user restart plasma-plasmashell.service
systemctl --user is-active plasma-plasmashell.service   # expect: active
ps -o pid,lstart,cmd -C plasmashell                      # one process, fresh start time
```

**Check first.** If `systemctl --user is-active plasma-plasmashell` says `inactive`
while `pgrep -a plasmashell` shows a process, someone started it by hand
(`plasmashell --replace`). `systemctl restart` will then fight that instance or do
nothing. Hand it back to systemd once:

```sh
kquitapp6 plasmashell                  # clean quit (waits for exit)
pgrep -x plasmashell                   # should print nothing
systemctl --user start plasma-plasmashell.service
```

**Don't:**
* `plasmashell --replace &`, `nohup …`, or `setsid plasmashell --replace` from an
  agent shell. These leave a shell process outside systemd that no unit tracks.
  Restart Plasma that way repeatedly and you end up with stray background jobs, and
  stdout/stderr go to `/dev/null` or a dead terminal, so QML errors are lost. (Earlier
  sessions did this; it was cleaned up 2026-10-14.)
* `killall plasmashell` — the unit has `Restart=on-failure`; a SIGKILL can restart it
  under you, or leave the panel gone if the unit wasn't the owner.

**After a restart, check for errors in your widget:**

```sh
journalctl --user -u plasma-plasmashell --since "-1min" --no-pager \
  | grep -iE '<widget-id or folder>|TypeError|ReferenceError'
```

Existing noise you can ignore: binding loops in `io.github.holty07.compactmediaplayer`
and "unknown wallpaper provider type".

**Screenshots:** `spectacle -b -n -f -o <file>`. The screen is at 2x scale, so double
the logical widget geometry when cropping.

## Sharing Guidelines for Agents

* When creating or editing a widget, verify `metadata.json` includes:
  * `KPackageStructure`: `Plasma/Applet`
  * `X-Plasma-API-Minimum-Version`: `6.0`
  * `X-Plasma-MainScript`, if set, points to an existing file. Plasma 6 defaults
    to `ui/main.qml`, and several widgets here omit the key.
  * `Id`: `io.github.holty07.<name>`; author `holty07`.
* Keep widget-specific READMEs for install/config details. Keep this repo README high-level.
* Record findings here in chronological sections under `## Widget Findings` or new `## Findings YYYY-MM-DD`.
* Do not commit secrets. Config files use `config.example.json` templates.
* The repo is public (github.com/holty07/plasma-widgets). No tokens, work email,
  employer references or `/home/<user>` paths in committed files.
* Test changes on Plasma 6 before marking complete.

## Findings 2026-10-28

### herdr-status idle count showing "…"
* Root cause: `hideIdle` defaulted to `true` in `contents/config/main.xml`. With `hideIdle` true, the idle DotAndCount gets `available: false`, so the panel hides the dot and renders "…" instead of the idle count.
* Fix: changed the `hideIdle` default to `false`. The user's `plasma-org.kde.plasma.desktop-appletsrc` sets no explicit `hideIdle` for any of the three herdrstatus applets, so all now fall back to the new default and show the idle count.
* Restarted `plasma-plasmashell.service` via systemd. No widget errors in the journal after restart.

## TODO for Agents
* Validate all widgets load in Plasma 6 panel and desktop contexts.
* Ensure QML imports use `org.kde.plasma.components` v3 etc., consistent with Plasma 6.
* Add CI notes for Plasma 6 version check if introduced.

---
Last updated: 2026-11-20
