#!/usr/bin/env python3
"""Install/remove the statusLine hook for the io.github.holty07.antigravityusage plasmoid.

Run:
    python3 setup-antigravity-usage-hook.py            # install
    python3 setup-antigravity-usage-hook.py --remove   # uninstall

What install does:
  1. Copies plasma-agy-statusline.py to ~/.gemini/antigravity-cli/plasma-agy-statusline.py
  2. Edits ~/.gemini/antigravity-cli/settings.json so statusLine runs that script
  3. If you already had a custom statusLine, backs it up under
     settings["_plasma_usage_previous_status_line"] instead of clobbering it

Restart antigravity-cli afterwards so it re-reads settings.json.
"""

from __future__ import annotations

import json
import os
import shutil
import sys

AGY_DIR = os.path.expanduser("~/.gemini/antigravity-cli")
SETTINGS_FILE = os.path.join(AGY_DIR, "settings.json")
HOOK_DEST = os.path.join(AGY_DIR, "plasma-agy-statusline.py")
HOOK_SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "plasma-agy-statusline.py")
STATUS_FILE = os.path.join(AGY_DIR, "plasma-agy-status.json")
BACKUP_KEY = "_plasma_usage_previous_status_line"
MARKER = "plasma-agy-statusline.py"


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
    os.makedirs(AGY_DIR, exist_ok=True)
    with open(SETTINGS_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


def _is_ours(status_line) -> bool:
    return (
        isinstance(status_line, dict)
        and isinstance(status_line.get("command"), str)
        and MARKER in status_line["command"]
    )


def install() -> None:
    os.makedirs(AGY_DIR, exist_ok=True)
    shutil.copyfile(HOOK_SRC, HOOK_DEST)
    os.chmod(HOOK_DEST, 0o755)

    settings = _load_settings()
    existing = settings.get("statusLine")

    if existing is not None and not _is_ours(existing):
        settings[BACKUP_KEY] = existing
        print("Backed up your existing statusLine to "
              f"settings.json[\"{BACKUP_KEY}\"].")

    settings["statusLine"] = {
        "type": "command",
        "command": f"python3 {HOOK_DEST}",
        "enabled": True,
    }
    _save_settings(settings)

    print(f"Installed hook script to {HOOK_DEST}")
    print(f"Set statusLine in {SETTINGS_FILE} to run it.")
    print("Restart antigravity-cli so it picks this up.")


def uninstall() -> None:
    settings = _load_settings()

    if _is_ours(settings.get("statusLine")):
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

    for path in (HOOK_DEST, STATUS_FILE):
        if os.path.exists(path):
            os.remove(path)
            print(f"Removed {path}")


if __name__ == "__main__":
    if "--remove" in sys.argv:
        uninstall()
    else:
        install()
