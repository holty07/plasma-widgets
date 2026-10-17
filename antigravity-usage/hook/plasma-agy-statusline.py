#!/usr/bin/env python3
"""antigravity-cli statusLine hook for the io.github.holty07.antigravityusage
plasmoid. Confirmed schema (captured directly from a real running session):

    {
      "model": {"id": "...", "display_name": "...", "effort": "high"},
      "workspace": {"current_dir": "...", "project_dir": "..."},
      "context_window": {
        "total_input_tokens": 0, "total_output_tokens": 0,
        "context_window_size": 1048576, "used_percentage": 0,
        "remaining_percentage": 100, "current_usage": null
      },
      "product": "antigravity",
      "quota": {
        "3p-weekly": {"remaining_fraction": 1, "reset_time": "...Z", "reset_in_seconds": 604799},
        "gemini-weekly": {"remaining_fraction": 0.74, "reset_time": "...Z", "reset_in_seconds": 535097}
      },
      "agent_state": "idle" | "initializing" | "authenticating" | (others while working),
      "plan_tier": "Antigravity Starter Quota",
      "email": "...",
      ...
    }

Writes it to ~/.gemini/antigravity-cli/plasma-agy-status.json for the KDE
plasmoid to read, and prints a short line back so the CLI's own status line
still shows something. No network calls of our own - this only captures
what antigravity-cli was already going to send to its statusLine hook.
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
from datetime import UTC, datetime
from typing import Any

STATUS_FILE = os.path.expanduser("~/.gemini/antigravity-cli/plasma-agy-status.json")


def render_statusline(data: dict[str, Any]) -> str:
    parts = []

    project = (data.get("workspace") or {}).get("project_dir")
    if isinstance(project, str) and project:
        parts.append(os.path.basename(project) or project)

    quota = data.get("quota") or {}
    gem = quota.get("gemini-weekly") or {}
    if "remaining_fraction" in gem:
        try:
            used = (1 - float(gem["remaining_fraction"])) * 100
            parts.append(f"gemini:{used:.0f}%")
        except (TypeError, ValueError):
            pass

    state = data.get("agent_state")
    if isinstance(state, str) and state:
        parts.append(state)

    return " | ".join(parts) if parts else "agy"


def save(data: dict[str, Any], now: datetime) -> None:
    data = dict(data)
    # The widget never shows the account email, so don't keep it on disk.
    data.pop("email", None)
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
        print("agy")
        return

    if not raw.strip():
        print("agy")
        return

    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        print("agy")
        return

    if not isinstance(data, dict):
        print("agy")
        return

    save(data, datetime.now(UTC))
    print(render_statusline(data))


if __name__ == "__main__":
    main()
