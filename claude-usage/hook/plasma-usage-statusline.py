#!/usr/bin/env python3
"""Claude Code statusLine hook for the io.github.holty07.claudeusage plasmoid.

Claude Code invokes whatever command is configured under `statusLine` in
~/.claude/settings.json every time it refreshes its status line, and feeds
that command a JSON blob on stdin describing the current session:

    {
      "workspace": {"project_dir": "/path/to/project"},
      "model": {"display_name": "Sonnet 4.6"},
      "context_window": {"used_percentage": 12, "context_window_size": 200000},
      "rate_limits": {
        "five_hour": {"used_percentage": 85, "resets_at": 1750000000},
        "seven_day": {"used_percentage": 33, "resets_at": 1750500000}
      },
      "cost": {"total_cost_usd": 38.73, "total_duration_ms": 3723000}
    }

This script does two things with that:
  1. Writes it straight to ~/.claude/plasma-usage-status.json (atomically),
     stamped with when we received it, so the KDE plasmoid can read it.
  2. Prints a short one-line status back to stdout, so your terminal still
     shows a normal Claude Code status line instead of going blank.

No network calls, no Anthropic API calls, nothing leaves this machine.
Deliberately stdlib-only so it runs under the system python3 with no venv.
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
from datetime import UTC, datetime
from typing import Any

STATUS_FILE = os.path.expanduser("~/.claude/plasma-usage-status.json")


def _pct(entry: dict[str, Any]) -> str:
    value = entry.get("used_percentage")
    if value is None:
        return "?"
    try:
        return f"{float(value):.0f}%"
    except (TypeError, ValueError):
        return "?"


def render_statusline(data: dict[str, Any]) -> str:
    """A minimal fallback status line so the terminal isn't left blank."""
    parts = []

    project = (data.get("workspace") or {}).get("project_dir")
    if isinstance(project, str) and project:
        parts.append(os.path.basename(project))

    rl = data.get("rate_limits") or {}
    five = rl.get("five_hour") or {}
    seven = rl.get("seven_day") or {}
    if "used_percentage" in five:
        parts.append(f"5h:{_pct(five)}")
    if "used_percentage" in seven:
        parts.append(f"7d:{_pct(seven)}")

    model = (data.get("model") or {}).get("display_name")
    if isinstance(model, str) and model:
        parts.append(model)

    return " | ".join(parts) if parts else "usage"


def save(data: dict[str, Any], now: datetime) -> None:
    data = dict(data)
    data["_received_at"] = now.isoformat()
    data["_received_at_ts"] = now.timestamp()

    target_dir = os.path.dirname(STATUS_FILE)
    os.makedirs(target_dir, exist_ok=True)

    tmp_path: str | None = None
    try:
        fd, tmp_path = tempfile.mkstemp(dir=target_dir, suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)
        os.replace(tmp_path, STATUS_FILE)
        tmp_path = None
    finally:
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.unlink(tmp_path)
            except OSError:
                pass


def main() -> None:
    try:
        raw = sys.stdin.read()
    except Exception:
        print("usage")
        return

    if not raw.strip():
        print("usage")
        return

    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        print("usage")
        return

    if not isinstance(data, dict):
        print("usage")
        return

    save(data, datetime.now(UTC))
    print(render_statusline(data))


if __name__ == "__main__":
    main()
