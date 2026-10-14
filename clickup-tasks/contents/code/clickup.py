#!/usr/bin/env python3
"""Fetch ClickUp tasks and print a compact JSON summary.

Invoked by the Plasma widget's "executable" DataSource (see ui/main.qml).
It keeps the API/pagination/auth logic out of QML and lets us test the
data path in plain Python. stdout carries only the JSON payload; logs go
to stderr.

Config (default ~/.config/clickup-tasks/config.json):
    {
      "token": "pk_...",          # ClickUp personal API token (required)
      "list_ids": [],             # optional: only these List IDs
      "assigned_to_me": true,     # only tasks assigned to the token's user
      "max_tasks": 100            # cap on tasks returned
    }
Override the path with --config or the CLICKUP_CONFIG env var.

Tasks come from GET /team/{team_id}/task ("filtered team tasks"), which
spans every List in a Workspace in pages of 100. Polling per List would
blow through ClickUp's 100 requests/minute limit on a large Workspace.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = "https://api.clickup.com/api/v2"
PAGE_SIZE = 100  # fixed by ClickUp for the team task endpoint


def log(msg):
    # stdout is reserved for the JSON payload the widget parses.
    print(msg, file=sys.stderr)


def now_ms():
    return int(time.time() * 1000)


def load_config(path=None):
    path = (
        path
        or os.environ.get("CLICKUP_CONFIG")
        or os.path.expanduser("~/.config/clickup-tasks/config.json")
    )
    cfg = {"token": "", "list_ids": [], "assigned_to_me": True, "max_tasks": 100}
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except FileNotFoundError:
        cfg["config_error"] = f"No config at {path}"
        return cfg
    except (json.JSONDecodeError, ValueError) as exc:
        cfg["config_error"] = f"Bad config {path}: {exc}"
        return cfg

    cfg["token"] = str(data.get("token", "") or "").strip()
    cfg["list_ids"] = [str(x).strip() for x in (data.get("list_ids") or []) if str(x).strip()]
    cfg["assigned_to_me"] = bool(data.get("assigned_to_me", True))
    cfg["max_tasks"] = int(data.get("max_tasks") or 100)
    return cfg


def api_get(token, path, params=None):
    url = BASE + path
    if params:
        url += "?" + urllib.parse.urlencode(params, doseq=True)
    request = urllib.request.Request(
        url, headers={"Authorization": token, "Accept": "application/json"}
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.loads(response.read().decode("utf-8"))


def fetch_team_tasks(token, team_id, user_id, list_ids, max_tasks):
    """Page through open tasks in one Workspace until last_page or the cap."""
    params = {
        "include_closed": "false",
        "subtasks": "true",
        "order_by": "due_date",
    }
    if user_id:
        params["assignees[]"] = [user_id]
    if list_ids:
        params["list_ids[]"] = list_ids

    tasks = []
    page = 0
    while len(tasks) < max_tasks:
        payload = api_get(token, f"/team/{team_id}/task", dict(params, page=page))
        batch = payload.get("tasks", [])
        tasks.extend(batch)
        if payload.get("last_page") or len(batch) < PAGE_SIZE:
            break
        page += 1
    return tasks


def due_ms(task):
    """ClickUp returns due_date as a millisecond epoch string (or null)."""
    due = task.get("due_date")
    try:
        return int(due) if due else None
    except (TypeError, ValueError):
        return None


def classify(status, due, now):
    """Map a ClickUp status + due date to a widget bucket."""
    if (status.get("type") or "").lower() in ("done", "closed"):
        return "done"
    if due and due < now:
        return "overdue"
    return "open"


def to_dict(task, now):
    """Flatten one ClickUp task into a compact, stable shape."""
    status = task.get("status") or {}
    priority = task.get("priority") or {}
    due = due_ms(task)
    return {
        "id": task.get("id"),
        "name": task.get("name", ""),
        "list": (task.get("list") or {}).get("name", ""),
        "status": status.get("status", ""),
        "status_color": status.get("color") or "#89b4fa",
        "priority": priority.get("priority", ""),
        "assignee": ", ".join(
            a.get("username") for a in task.get("assignees") or [] if a.get("username")
        ),
        "due": due,
        "url": task.get("url", ""),
        "bucket": classify(status, due, now),
    }


def main(argv):
    config_path = None
    if "--config" in argv:
        config_path = argv[argv.index("--config") + 1]
    cfg = load_config(config_path)

    result = {
        "received_at": now_ms(),
        "ok": False,
        "counts": {"overdue": 0, "open": 0, "done": 0, "total": 0},
        "tasks": [],
        "error": "",
    }

    def fail(message):
        result["error"] = message
        print(json.dumps(result))
        return 1

    if cfg.get("config_error"):
        return fail(cfg["config_error"])
    token = cfg["token"]
    if not token:
        return fail("Missing ClickUp token")

    try:
        user_id = api_get(token, "/user")["user"]["id"] if cfg["assigned_to_me"] else None
        teams = api_get(token, "/team").get("teams", [])
    except urllib.error.HTTPError as exc:
        return fail(f"ClickUp auth failed (HTTP {exc.code})")
    except Exception as exc:  # noqa: BLE001 - offline, DNS, etc.
        return fail(f"Cannot reach ClickUp: {exc}")

    now = now_ms()
    all_tasks = []
    errors = []
    for team in teams:
        try:
            raw = fetch_team_tasks(token, team["id"], user_id, cfg["list_ids"], cfg["max_tasks"])
            all_tasks.extend(to_dict(t, now) for t in raw)
        except urllib.error.HTTPError as exc:
            errors.append(f"{team.get('name', team['id'])}: HTTP {exc.code}")
        except Exception as exc:  # noqa: BLE001 - report any fetch failure
            errors.append(f"{team.get('name', team['id'])}: {exc}")
    for err in errors:
        log(f"[clickup] {err}")
    if errors and not all_tasks:
        return fail("; ".join(errors))

    # Overdue first, then open, then done; soonest due date first in each.
    order = {"overdue": 0, "open": 1, "done": 2}
    all_tasks.sort(key=lambda t: (order[t["bucket"]], t["due"] or float("inf")))

    counts = {"overdue": 0, "open": 0, "done": 0}
    for task in all_tasks:
        counts[task["bucket"]] += 1
    result["counts"] = dict(counts, total=len(all_tasks))
    result["tasks"] = all_tasks[: cfg["max_tasks"]]
    result["ok"] = True
    result["error"] = "; ".join(errors)
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
