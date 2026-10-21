#!/usr/bin/env python3
"""List the Orca panes that have a Hermes Agent running in them.

Invoked by the Plasma widget's "executable" DataSource (see ui/main.qml).
Orca often has no status row for Hermes: its orca-status hook events don't
always land, and the TUI pane isn't tagged with an agentIdentity either. So
this finds Hermes processes directly. Orca exports ORCA_PANE_KEY into every
pane's shell, and Hermes inherits it.

A process counts as Hermes when its executable lives under the Hermes home
(the installer bundles its own python and node there) or when it was started
through a `hermes` launcher script.

stdout carries only the JSON payload: ["<paneKey>", ...].
"""

import json
import os


def hermes_home():
    # Mirrors Hermes's own get_hermes_home().
    override = os.environ.get("HERMES_HOME", "").strip()
    if override:
        return os.path.realpath(os.path.expanduser(override))
    suffix = os.environ.get("HERMES_DATA_DIR_SUFFIX", "")
    return os.path.realpath(os.path.expanduser("~/.hermes" + suffix))


def is_hermes(pid, home):
    try:
        exe = os.readlink(f"/proc/{pid}/exe")
    except OSError:
        return False
    if exe.startswith(home + os.sep):
        return True
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        argv = f.read().split(b"\0")[:2]
    return any(os.path.basename(arg) == b"hermes" for arg in argv)


def pane_key(pid):
    with open(f"/proc/{pid}/environ", "rb") as f:
        for entry in f.read().split(b"\0"):
            if entry.startswith(b"ORCA_PANE_KEY="):
                return entry.split(b"=", 1)[1].decode()
    return ""


def main():
    home = hermes_home()
    uid = os.getuid()
    panes = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            if os.stat(f"/proc/{name}").st_uid != uid or not is_hermes(name, home):
                continue
            key = pane_key(name)
        except OSError:
            # The process exited while we were reading it.
            continue
        if key:
            panes.add(key)
    print(json.dumps(sorted(panes)))


if __name__ == "__main__":
    main()
