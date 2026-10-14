# ClickUp Tasks — setup
#
# 1. Get a personal API token
#    - Log in to ClickUp
#    - Settings -> Apps -> API Token (or "My Access Tokens")
#    - Copy the token (it starts with `pk_`)
#
# 2. Configure the widget
#    - mkdir -p ~/.config/clickup-tasks
#    - cp config.example.json ~/.config/clickup-tasks/config.json
#    - chmod 600 ~/.config/clickup-tasks/config.json
#    - Put the token in "token". By default the widget shows open tasks
#      assigned to you across every Workspace the token can see.
#      Optional: "list_ids" limits it to specific Lists (the number after
#      /li/ in a List URL); "assigned_to_me": false shows everyone's tasks.
#
# 3. Check the payload
#        python3 contents/code/clickup.py
#    JSON goes to stdout, logs to stderr. --config <path> or CLICKUP_CONFIG
#    overrides the config location for testing.
#
# 4. Install the applet
#    - Symlink the folder into your Plasma applet directory:
#        ln -s "$PWD" ~/.local/share/plasma/plasmoids/io.github.holty07.clickuptasks
#    - Reload: systemctl --user restart plasma-plasmashell.service
#
# 5. Test it as Plasma would
#    - The widget runs: python3 '<package>/contents/code/clickup.py' every 5 min
#    - Make sure `python3` on PATH resolves in the same user session the
#      panel runs in (the `executable` DataSource inherits the session env).

## How tasks are fetched
# GET /api/v2/team/{team_id}/task ("filtered team tasks") spans every List in
# a Workspace, 100 tasks per page, so a refresh costs a few requests. Polling
# each List separately hits the 100 requests/minute limit on big Workspaces.
#
# Auth note: this uses a Personal API token (starts `pk_`), which never
# expires and is intended for personal integrations. It is sent raw in the
# `Authorization` header (no `Bearer` prefix). ClickUp rate-limits at 100
# requests/minute per token.
