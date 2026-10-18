# Claude Usage

Panel: a small pie showing your current 5-hour session % used.
Desktop: full breakdown with session %, weekly %, context window, cost, model and project.

No network calls, no login, no scraping. Claude Code passes a JSON blob with your rate-limit percentages, context window, cost and model to its `statusLine` command. The hook in `hook/` saves that JSON to `~/.claude/plasma-usage-status.json`, and the widget reads it. If the hook hasn't run yet, the widget falls back to Claude Code's own cached quota in `~/.claude.json` (fewer details, no setup).

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
