# FreeLLMAPI Usage — Plasma Widget

Tracks freellmapi dashboard usage and detects model-catalog changes.

## Install

```bash
ln -s "$PWD/freellmapi-usage" ~/.local/share/plasma/plasmoids/io.github.holty07.freellmapiusage
systemctl --user restart plasma-plasmashell.service
```

## Config

Copy `config.example.json` to `~/.config/freellmapi-usage/config.json` and fill in `session_token`. Token is valid until logout/restart.

The widget reads the REST API at `/api/analytics/*` gated by the dashboard session token and falls back to read-only SQLite queries (PRAGMA query_only) for model-change detection.

## Model changes

The Python fetcher stores the last known `catalog_applied_version` and `catalog_applied_*` settings from `settings`. On each refresh it compares to current DB values and flags added/removed/changed models.

## Data sources

- REST: `GET /summary`, `/by-model`, `/by-platform`, `/by-client`, `/timeline`
- SQLite read-only: `models`, `settings` (catalog version), `request_hourly`, `api_keys`
