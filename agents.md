# Agents

This document collects findings from agents working in this Plasma Widgets repository and defines conventions for sharing information.

## Plasma 6 Requirement

Finding: All widgets currently target KDE Plasma 6.

* `agenda/metadata.json` → `X-Plasma-API-Minimum-Version: 6.0`
* `claude-usage/metadata.json` → `X-Plasma-API-Minimum-Version: 6.0`
* `clickup-tasks/metadata.json` → `X-Plasma-API-Minimum-Version: 6.0`
* `freellmapi-usage/metadata.json` → `X-Plasma-API-Minimum-Version: 6.0`
* `orca-notifier/metadata.json` → `X-Plasma-API-Minimum-Version: 6.0`

Implication: Ensure built widgets will work on Plasma 6. Do not use Plasma 5 APIs, Qt5 imports, or Plasma Shell 5 components. Build/test against Qt 6 / Kirigami 2 / Plasma 6.

## Widget Findings

### freellmapi-usage
* Modified recently. Contains Python fetcher `contents/code/freellmapi.py`.
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
* Category System Information.

### clickup-tasks
* Python fetcher `contents/code/clickup.py`.
* Config files: `config.example.json`, `config.json`.
* Own README exists.

### orca-notifier
* Displays Orca agents: active, idle, waiting for input.
* Id `org.kde.plasma.orca-notifier`.
* `X-Plasma-API` set to `declarativeappletscript`.

## Sharing Guidelines for Agents

* When creating or editing a widget, verify `metadata.json` includes:
  * `KPackageStructure`: `Plasma/Applet`
  * `X-Plasma-API-Minimum-Version`: `6.0`
  * `X-Plasma-MainScript` points to existing `ui/main.qml`
* Keep widget-specific READMEs for install/config details. Keep this repo README high-level.
* Record findings here in chronological sections under `## Widget Findings` or new `## Findings YYYY-MM-DD`.
* Do not commit secrets. Config files use `config.example.json` templates.
* Test changes on Plasma 6 before marking complete.

## TODO for Agents
* Validate all widgets load in Plasma 6 panel and desktop contexts.
* Ensure QML imports use `org.kde.plasma.components` v3 etc., consistent with Plasma 6.
* Add CI notes for Plasma 6 version check if introduced.

---
Last updated: 2026-10-14
