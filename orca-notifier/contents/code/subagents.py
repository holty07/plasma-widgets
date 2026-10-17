#!/usr/bin/env python3
"""List the Claude Code sub-agents still running under each Orca pane.

Invoked by the Plasma widget's "executable" DataSource (see ui/main.qml).
`orca worktree ps` drops the sub-agent roster Orca keeps internally, so this
reads the same files Orca does:

* ~/.config/orca/agent-hooks/last-status.json maps each pane to the
  transcript of the Claude session running in it.
* Claude writes each sub-agent's transcript to
  <session>/subagents/agent-<id>.jsonl, with type, model and description in
  the matching .meta.json.

A sub-agent is running until its transcript ends with Orca's SubagentStop
hook. Sub-agents killed mid-run never get that hook, so a transcript that
hasn't been written for STALE_SECONDS also counts as finished.

stdout carries only the JSON payload: {"<paneKey>": [{...}, ...]}.
"""

import glob
import json
import os
import sys
import time

STATUS_FILE = os.path.expanduser("~/.config/orca/agent-hooks/last-status.json")
# Matches Orca's own cutoff for trusting agent status evidence.
STALE_SECONDS = 30 * 60
# Enough of the transcript tail to find the last tool call and the stop hook.
TAIL_BYTES = 64 * 1024


def read_tail(path):
    with open(path, "rb") as f:
        f.seek(0, os.SEEK_END)
        size = f.tell()
        f.seek(max(0, size - TAIL_BYTES))
        data = f.read()
    lines = data.splitlines()
    # The first line is probably cut in half unless we read from the start.
    if size > TAIL_BYTES:
        lines = lines[1:]
    entries = []
    for line in lines:
        try:
            entries.append(json.loads(line))
        except ValueError:
            pass
    return entries


def first_timestamp(path):
    with open(path, "rb") as f:
        try:
            return json.loads(f.readline()).get("timestamp")
        except ValueError:
            return None


def to_ms(stamp):
    # "2026-10-17T03:41:07.123Z" -> epoch milliseconds.
    if not stamp:
        return 0
    try:
        t = time.strptime(stamp[:19], "%Y-%m-%dT%H:%M:%S")
        return int(time.mktime(t) - time.timezone) * 1000
    except ValueError:
        return 0


def subagent_info(path, now):
    if now - os.path.getmtime(path) > STALE_SECONDS:
        return None
    entries = read_tail(path)
    tool = ""
    for entry in entries:
        attachment = entry.get("attachment") or {}
        if attachment.get("hookEvent") == "SubagentStop":
            return None
        message = entry.get("message") or {}
        if entry.get("type") == "assistant" and isinstance(message.get("content"), list):
            for block in message["content"]:
                if block.get("type") == "tool_use":
                    tool = block.get("name") or ""
    meta = {}
    try:
        with open(path[: -len(".jsonl")] + ".meta.json") as f:
            meta = json.load(f)
    except (OSError, ValueError):
        pass
    return {
        "id": os.path.basename(path)[len("agent-"): -len(".jsonl")],
        "description": meta.get("description") or "",
        "agentType": meta.get("agentType") or "",
        "model": meta.get("model") or "",
        "tool": tool,
        "startedAt": to_ms(first_timestamp(path)),
    }


def main():
    try:
        with open(STATUS_FILE) as f:
            entries = json.load(f).get("entries") or {}
    except (OSError, ValueError) as e:
        print(f"cannot read {STATUS_FILE}: {e}", file=sys.stderr)
        print("{}")
        return
    now = time.time()
    result = {}
    for pane_key, entry in entries.items():
        transcript = (entry.get("providerSession") or {}).get("transcriptPath")
        if not transcript or not transcript.endswith(".jsonl"):
            continue
        pattern = os.path.join(glob.escape(transcript[: -len(".jsonl")]),
                               "subagents", "agent-*.jsonl")
        running = []
        for path in glob.glob(pattern):
            try:
                info = subagent_info(path, now)
            except OSError:
                continue
            if info:
                running.append(info)
        if running:
            running.sort(key=lambda s: s["startedAt"])
            result[pane_key] = running
    print(json.dumps(result))


if __name__ == "__main__":
    main()
