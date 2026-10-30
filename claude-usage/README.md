# Claude Usage

Panel: a small pie showing your current 5-hour session % used.
Desktop: full breakdown with session %, weekly %, context window, cost, model and project.

No network calls, no login, no scraping. The widget reads four local sources and shows whichever saw your limits most recently (the footer says which):

| Source | Where | Notes |
|--------|-------|-------|
| Cindy | `account_usage_snapshots` in the newest `~/.config/CindyGlobal/cindy-*.db` | Updated on every Claude turn Cindy runs. Cindy doesn't fire the statusLine hook. |
| statusLine hook | `~/.claude/plasma-usage-status.json` | Written by the hook in `hook/` whenever the Claude Code CLI redraws its status line. Only source with context, cost and model. |
| Claude Code cache | `~/.claude.json` → `cachedUsageUtilization` | No setup needed. |
| Claude desktop app | `~/.config/Claude/plan-usage-history.json` | Only updated while the desktop app runs. No reset times. |

If the hook data is under 6 hours old, its context, cost and model are shown alongside whichever percentages win.

The 5-hour and 7-day limits are one pool shared across Claude Code, Claude.ai chat and Cowork, so the numbers cover all three.

## Install

```bash
ln -s "$PWD/claude-usage" ~/.local/share/plasma/plasmoids/io.github.holty07.claudeusage
systemctl --user restart plasma-plasmashell.service
```

Then add **Claude Usage** from Add Widgets to your panel and/or desktop.

## Hook setup (live data)

```bash
python3 claude-usage/hook/setup-claude-usage-hook.py            # install
python3 claude-usage/hook/setup-claude-usage-hook.py --remove   # uninstall
```

Install copies `plasma-usage-statusline.py` to `~/.claude/` and points `statusLine` in `~/.claude/settings.json` at it. If you already had a statusLine, it is backed up under `_plasma_usage_previous_status_line` and restored on `--remove`.

Restart Claude Code (or start a new session) so it re-reads `settings.json`.

Skipping this step is fine: the widget still shows session and weekly % from Claude Code's cache, just without cost, context or model.
