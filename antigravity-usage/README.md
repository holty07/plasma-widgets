# Antigravity Usage

Shows antigravity-cli's weekly quota (`gemini-weekly` as the ring, `3p-weekly` as the bar) and context-window usage. Pie in the panel, full breakdown on the desktop.

## Install

```bash
ln -s "$PWD/antigravity-usage" ~/.local/share/plasma/plasmoids/io.github.holty07.antigravityusage
systemctl --user restart plasma-plasmashell.service
```

## Hook setup

antigravity-cli passes its usage data to a statusLine command. The hook in `hook/` saves that data to `~/.gemini/antigravity-cli/plasma-agy-status.json`, which the widget reads. It makes no network calls of its own and drops the account email before saving.

```bash
python3 antigravity-usage/hook/setup-antigravity-usage-hook.py            # install
python3 antigravity-usage/hook/setup-antigravity-usage-hook.py --remove   # uninstall
```

Install copies `plasma-agy-statusline.py` into `~/.gemini/antigravity-cli/` and points `statusLine` in `settings.json` at it. If you already had a statusLine, it is backed up under `_plasma_usage_previous_status_line` and restored on `--remove`.

Restart antigravity-cli afterwards, then run a prompt so the widget gets its first update.
