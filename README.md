# Plasma Widgets

KDE Plasma 6 plasmoids developed for personal use. All widgets target **KDE Plasma 6** and declare `X-Plasma-API-Minimum-Version: 6.0` in `metadata.json`. Ensure your system is running Plasma 6 before installing.

## Overview

This folder contains multiple Plasma Applet projects, each in its own subdirectory with the standard `contents/ui`, `contents/code`, and `metadata.json` layout.

### Widgets

| Folder | Name | Category | Purpose |
|--------|------|----------|---------|
| `agenda` | Agenda | Date and Time | Today's agenda from Google Calendar ICS feeds — Catppuccin Mocha |
| `claude-usage` | Claude Usage | System Information | Claude Code session/weekly usage — pie in panel, full breakdown on desktop |
| `clickup-tasks` | ClickUp Tasks | Utilities | ClickUp task lists: overdue/open/done counts, with task list on desktop |
| `freellmapi-usage` | FreeLLMAPI Usage | System Information | Tracks freellmapi usage: requests, tokens, latency, cost savings by model/platform, with model-catalog change detection |
| `orca-notifier` | Orca Notifier | System Information | Displays current Orca agents: active, idle, and waiting for input |

## Plasma 6 Compatibility

* All widgets require **KDE Plasma 6** (`X-Plasma-API-Minimum-Version: 6.0`).
* Tested on Plasma 6. Build with Qt 6 / Kirigami 2 and Plasma Shell 6 APIs.
* If you are on Plasma 5, widgets will not load. Upgrade to Plasma 6 to use these.

Installation pattern (example):

```bash
ln -s "$PWD/<widget-folder>" ~/.local/share/plasma/plasmoids/<plugin-id>
systemctl --user restart plasma-plasmashell.service
```

See each widget's own README for config details.

## Project Structure

```
Plasma Widgets/
├─ agenda/
├─ claude-usage/
├─ clickup-tasks/
├─ freellmapi-usage/
├─ orca-notifier/
├─ README.md
└─ agents.md
```

## Agents

See `agents.md` for findings from other agents, conventions, and sharing guidelines.

## License

Widgets use GPL-2.0-or-later or GPL-3.0-or-later as per their individual `metadata.json`.
