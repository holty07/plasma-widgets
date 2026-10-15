#!/usr/bin/env python3
"""Fetch freellmapi analytics and detect model-catalog changes.

stdout: compact JSON for the QML widget.
stderr: logs.
"""
import json
import os
import sys
import time
import urllib.request
import urllib.error
import sqlite3

def log(msg):
    print(msg, file=sys.stderr)

def now_ms():
    return int(time.time() * 1000)

def load_config(path=None):
    path = path or os.environ.get("FREELLMAPI_CONFIG") or os.path.expanduser("~/.config/freellmapi-usage/config.json")
    cfg = {
        "session_token": "",
        "api_base": "http://127.0.0.1:3001/api/analytics",
        "db_path": "~/freellmapi/server/data/freeapi.db",
        "range": "7d",
        "auto_refresh_interval": 300,
        "refresh_on_click": True,
        "show_model_changes": True,
        "catalog_version_file": os.path.expanduser("~/.cache/freellmapi-usage/catalog_version.json"),
    }
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        cfg.update(data)
    except FileNotFoundError:
        cfg["config_error"] = f"No config at {path}"
    except Exception as e:
        cfg["config_error"] = f"Bad config {path}: {e}"
    return cfg

def api_get(token, base, path):
    url = base.rstrip("/") + path
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}", "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode("utf-8"))

def fetch_rest(cfg):
    token = cfg.get("session_token","").strip()
    base = cfg.get("api_base","")
    range_ = cfg.get("range","7d")
    if not token or not base:
        return None
    try:
        summary = api_get(token, base, f"/summary?range={range_}")
        by_model = api_get(token, base, f"/by-model?range={range_}")
        by_platform = api_get(token, base, f"/by-platform?range={range_}")
        by_client = api_get(token, base, f"/by-client?range={range_}")
        timeline = api_get(token, base, f"/timeline?range={range_}")
        return {"summary": summary, "by_model": by_model, "by_platform": by_platform, "by_client": by_client, "timeline": timeline}
    except urllib.error.HTTPError as e:
        log(f"[freellmapi] HTTP {e.code} {e.reason}")
        return None
    except Exception as e:
        log(f"[freellmapi] REST error: {e}")
        return None

def db_readonly_query(db_path, sql, params=()):
    try:
        con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        con.execute("PRAGMA query_only=ON")
        cur = con.cursor()
        cur.execute(sql, params)
        rows = cur.fetchall()
        cols = [d[0] for d in cur.description] if cur.description else []
        con.close()
        return [dict(zip(cols, r)) for r in rows]
    except Exception as e:
        log(f"[freellmapi] DB error: {e}")
        return []

def detect_model_changes(cfg, catalog_version_cache):
    db_path = cfg.get("db_path")
    if not db_path:
        return {"changed": False}
    # Get settings
    settings_rows = db_readonly_query(db_path, "SELECT key,value FROM settings WHERE key IN ('catalog_applied_version','catalog_applied_tier','catalog_applied_json','total_input_tokens','total_output_tokens','total_requests','first_request_at')")
    settings = {r["key"]: r["value"] for r in settings_rows}
    current_version = settings.get("catalog_applied_version","")
    current_tier = settings.get("catalog_applied_tier","")
    # load last known
    last_version = catalog_version_cache.get("version","")
    last_tier = catalog_version_cache.get("tier","")
    changed = current_version != last_version or current_tier != last_tier
    # model counts
    model_count = db_readonly_query(db_path, "SELECT COUNT(*) as cnt FROM models WHERE enabled=1")
    enabled_count = model_count[0]["cnt"] if model_count else 0
    total_count = db_readonly_query(db_path, "SELECT COUNT(*) as cnt FROM models")
    total = total_count[0]["cnt"] if total_count else 0
    # disabled models
    disabled = db_readonly_query(db_path, "SELECT platform,model_id,display_name,monthly_token_budget FROM models WHERE enabled=0")
    # models with explicit token budgets (not free/unlimited)
    budgeted = db_readonly_query(db_path, """
        SELECT platform,model_id,display_name,monthly_token_budget,paid_input_per_m,paid_output_per_m
        FROM models WHERE enabled=1 AND monthly_token_budget != '' AND monthly_token_budget NOT LIKE '%free%' 
        ORDER BY intelligence_rank DESC LIMIT 20
    """)
    result = {
        "changed": changed,
        "current_version": current_version,
        "last_version": last_version,
        "current_tier": current_tier,
        "last_tier": last_tier,
        "enabled_models": enabled_count,
        "total_models": total,
        "disabled_models": disabled,
        "models_with_budget": budgeted,
        "catalog_applied_at": settings.get("catalog_last_sync_ms",""),
        "lifetime_totals": {
            "total_requests": float(settings.get("total_requests",0) or 0),
            "total_input_tokens": float(settings.get("total_input_tokens",0) or 0),
            "total_output_tokens": float(settings.get("total_output_tokens",0) or 0),
            "first_request_at": settings.get("first_request_at","")
        }
    }
    return result

def load_cache(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return {}

def save_cache(path, data):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(data, fh)
    except Exception as e:
        log(f"[freellmapi] cache save error: {e}")

def main(argv):
    cfg_path = None
    if "--config" in argv:
        cfg_path = argv[argv.index("--config")+1]
    cfg = load_config(cfg_path)
    out = {
        "received_at": now_ms(),
        "ok": False,
        "config_error": cfg.get("config_error",""),
        "error": "",
        "range": cfg.get("range","7d"),
        "data": None,
        "model_changes": None
    }
    if out["config_error"]:
        out["error"] = out["config_error"]
        print(json.dumps(out))
        return 1
    # REST
    rest = fetch_rest(cfg)
    if rest is None:
        out["error"] = "REST API unavailable or bad token"
    else:
        out["data"] = rest
    # Model changes + token budgets
    cache_path = os.path.expanduser(cfg.get("catalog_version_file",""))
    cache = load_cache(cache_path) if cfg.get("show_model_changes") else {}
    changes = detect_model_changes(cfg, cache)
    out["model_changes"] = changes
    if cfg.get("show_model_changes"):
        if changes["changed"]:
            save_cache(cache_path, {"version": changes["current_version"], "tier": changes["current_tier"]})
    out["ok"] = True
    print(json.dumps(out))
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
