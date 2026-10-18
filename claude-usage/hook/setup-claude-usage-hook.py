#!/usr/bin/env python3
"""Install/remove the statusLine hook for the io.github.holty07.claudeusage plasmoid.

Run:
    python3 setup-claude-usage-hook.py            # install
    python3 setup-claude-usage-hook.py --remove    # uninstall

What install does:
  1. Copies plasma-usage-statusline.py to ~/.claude/plasma-usage-statusline.py
  2. Edits ~/.claude/settings.json so statusLine runs that script
  3. If you already had a custom statusLine, backs it up under
     settings["_plasma_usage_previous_status_line"] instead of clobbering it

Restart Claude Code afterwards so it re-reads settings.json.
"""

from __future__ import annotations

import json
import os
import shutil
import sys

CLAUDE_DIR = os.path.expanduser("~/.claude")
SETTINGS_FILE = os.path.join(CLAUDE_DIR, "settings.json")
HOOK_DEST = os.path.join(CLAUDE_DIR, "plasma-usage-statusline.py")
HOOK_SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "plasma-usage-statusline.py")
BACKUP_KEY = "_plasma_usage_previous_status_line"
MARKER = "plasma-usage-statusline.py"


def _load_settings() -> dict:
    if not os.path.exists(SETTINGS_FILE):
        return {}
    try:
        with open(SETTINGS_FILE, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        print(f"Warning: couldn't parse {SETTINGS_FILE}, leaving it untouched.")
        sys.exit(1)
    return data if isinstance(data, dict) else {}


def _save_settings(data: dict) -> None:
    os.makedirs(CLAUDE_DIR, exist_ok=True)
    with open(SETTINGS_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


def _hook_command() -> str:
    return f"python3 {HOOK_DEST}"


def install() -> None:
    os.makedirs(CLAUDE_DIR, exist_ok=True)
    shutil.copyfile(HOOK_SRC, HOOK_DEST)
    os.chmod(HOOK_DEST, 0o755)

    settings = _load_settings()
    existing = settings.get("statusLine")

    already_ours = (
        isinstance(existing, dict)
        and isinstance(existing.get("command"), str)
        and MARKER in existing["command"]
    )

    if existing is not None and not already_ours:
        settings[BACKUP_KEY] = existing
        print("Backed up your existing statusLine to "
              f"settings.json[\"{BACKUP_KEY}\"].")

    settings["statusLine"] = {"type": "command", "command": _hook_command()}
    _save_settings(settings)

    print(f"Installed hook script to {HOOK_DEST}")
    print(f'Set statusLine in {SETTINGS_FILE} to run it.')
    print("Restart Claude Code (or open a new session) so it picks this up.")


def uninstall() -> None:
    settings = _load_settings()
    sl = settings.get("statusLine")
    is_ours = (
        isinstance(sl, dict)
        and isinstance(sl.get("command"), str)
        and MARKER in sl["command"]
    )

    if is_ours:
        previous = settings.pop(BACKUP_KEY, None)
        if previous is not None:
            settings["statusLine"] = previous
            print("Restored your previous statusLine.")
        else:
            settings.pop("statusLine", None)
            print("Removed statusLine (you had none configured before).")
        _save_settings(settings)
    else:
        print("statusLine wasn't pointed at our hook — leaving settings.json untouched.")

    if os.path.exists(HOOK_DEST):
        os.remove(HOOK_DEST)
        print(f"Removed {HOOK_DEST}")

    status_file = os.path.join(CLAUDE_DIR, "plasma-usage-status.json")
    if os.path.exists(status_file):
        os.remove(status_file)
        print(f"Removed {status_file}")


if __name__ == "__main__":
    if "--remove" in sys.argv:
        uninstall()
    else:
        install()
