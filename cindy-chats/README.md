# Cindy Chats

Shows live Cindy chat states in the panel (compact dots) and desktop (full list).

- **Working** (blue) — agent is actively processing
- **Waiting** (yellow) — agent is waiting for your input
- **Idle** (green) — ready for a new task

Also includes a **Usage Tracker** section at the bottom of the desktop view showing:

- **Claude Code**: 5-hour session limit and 7-day weekly limit
- **antigravity-cli (agy)**: Gemini weekly and 3p weekly quotas

## Install

```bash
ln -s "$PWD/cindy-chats" ~/.local/share/plasma/plasmoids/io.github.holty07.cindychats
systemctl --user restart plasma-plasmashell.service
```

Then add **Cindy Chats** from Add Widgets to your panel and/or desktop.

## Configuration

Right-click the widget → Configure to set:

- **Database path** — Path to the Cindy SQLite database (default: `~/.config/CindyGlobal/cindy-cmvsyhcia10i9yw01rst1i34s.db`)
- **Poll interval** — Seconds between database polls (default: 5)
- **Show idle chats in panel** — Show the green idle dot in compact view
- **Request attention when waiting** — Highlight panel when chats are waiting for you

## Usage Tracker Data Sources

The usage tracker reads from local files (no network calls). For Claude, the
freshest of the first three sources wins:

| Source | File | Required For |
|--------|------|--------------|
| Cindy database | `account_usage_snapshots` in the database above | Live Claude % + reset times, updated on every Cindy turn |
| Claude desktop app cache | `~/.config/Claude/plan-usage-history.json` | Basic Claude % (always present if app runs) |
| Claude Code hook | `~/.claude/plasma-usage-status.json` | Full Claude detail (cost, context, model) |
| antigravity-cli hook | `~/.gemini/antigravity-cli/plasma-agy-status.json` | agy quotas, context, model, agent state |
| Fallback | `~/.claude.json` | Basic Claude % if hooks not installed |

### Hook Setup (for live detailed data)

**Claude Code:**
```bash
python3 ~/.local/share/plasma/plasmoids/io.github.holty07.claudeusage/hook/setup-claude-usage-hook.py
# then restart Claude Code
```

**antigravity-cli (agy):**
```bash
python3 ~/.local/share/plasma/plasmoids/io.github.holty07.antigravityusage/hook/setup-antigravity-usage-hook.py
# then restart antigravity-cli
```

Without hooks, the widget still shows basic percentages from the Claude desktop app cache and `~/.claude.json` fallback. antigravity requires its hook for any data.

## Panel (Compact)

Three colored dots with counts:
- Blue = working
- Yellow = waiting
- Green = idle (optional)

Middle-click to force refresh. Left-click to expand.

## Desktop (Full)

Scrollable list of active chats with:
- Agent icon (Claude, Codex, Gemini, Hermes, etc.)
- Chat title
- Working directory + model
- Current state badge

Below the list: **Usage Tracker** with bars for each quota.