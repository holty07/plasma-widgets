.pragma library

// Reads antigravity-cli's local usage data via our statusLine hook at
// ~/.gemini/antigravity-cli/plasma-agy-status.json. No network calls, no
// OAuth token extraction, nothing leaves this machine — same principle as
// the Claude widget, just a different (and in this case richer) schema.
//
// Confirmed schema (captured live from a real session):
//   quota: { "gemini-weekly": {remaining_fraction, reset_time, reset_in_seconds},
//            "3p-weekly": {...same shape...} }
//   context_window: { used_percentage, context_window_size, ... }
//   agent_state: "idle" | "initializing" | "authenticating" | (others while working)
//   model: { display_name, effort }
//   plan_tier, workspace.project_dir
//
// Unlike Claude Code, there's no separate "session (5h)" concept here —
// everything is weekly-scoped. We use "gemini-weekly" as the primary
// number (the ring) since it's the one that actually accrues usage day to
// day, and "3p-weekly" as the secondary bar.

function clampPct(v) {
    var n = parseFloat(v)
    if (isNaN(n)) return null
    return Math.max(0, Math.min(100, Math.round(n)))
}

function isoToTs(s) {
    var t = new Date(s).getTime()
    if (isNaN(t)) return null
    return t / 1000
}

function emptySnapshot() {
    return {
        available: false,
        sessionPct: null,       // "gemini-weekly" used % (primary, the ring)
        sessionResetsAt: null,
        weeklyPct: null,        // "3p-weekly" used % (secondary bar)
        weeklyResetsAt: null,
        contextPct: null,
        contextSize: null,
        model: "",
        effort: "",
        project: "",
        planTier: "",
        agentState: "",
        receivedAt: null,
        source: "none"
    }
}

function usedPctFromRemainingFraction(remain) {
    if (remain === undefined || remain === null) return null
    var n = parseFloat(remain)
    if (isNaN(n)) return null
    return clampPct((1 - n) * 100)
}

function fromHookPayload(text) {
    var data
    try {
        data = JSON.parse(text)
    } catch (e) {
        return null
    }
    if (!data || typeof data !== "object") return null

    var quota = data.quota || {}
    var gem = quota["gemini-weekly"] || {}
    var thirdParty = quota["3p-weekly"] || {}

    if (gem.remaining_fraction === undefined && thirdParty.remaining_fraction === undefined) {
        return null
    }

    var ctx = data.context_window || {}
    var workspace = data.workspace || {}
    var model = data.model || {}

    var snap = emptySnapshot()
    snap.available = true
    snap.sessionPct = usedPctFromRemainingFraction(gem.remaining_fraction)
    snap.sessionResetsAt = gem.reset_time ? isoToTs(gem.reset_time) : null
    snap.weeklyPct = usedPctFromRemainingFraction(thirdParty.remaining_fraction)
    snap.weeklyResetsAt = thirdParty.reset_time ? isoToTs(thirdParty.reset_time) : null
    snap.contextPct = (ctx.used_percentage !== undefined) ? clampPct(ctx.used_percentage) : null
    snap.contextSize = ctx.context_window_size || null
    snap.model = model.display_name || ""
    snap.effort = model.effort || ""
    snap.project = workspace.project_dir ? String(workspace.project_dir).split("/").pop() : ""
    snap.planTier = data.plan_tier || ""
    snap.agentState = data.agent_state || ""
    snap.receivedAt = (data._received_at_ts !== undefined) ? data._received_at_ts : (Date.now() / 1000)
    snap.source = "hook"
    return snap
}

function fmtDuration(seconds) {
    if (seconds === null || seconds === undefined || isNaN(seconds)) return ""
    seconds = Math.max(0, Math.round(seconds))
    var h = Math.floor(seconds / 3600)
    var m = Math.floor((seconds % 3600) / 60)
    if (h > 0) return h + "h " + m + "m"
    var s = seconds % 60
    if (m > 0) return m + "m " + s + "s"
    return s + "s"
}

function fmtTokens(n) {
    if (n === null || n === undefined) return ""
    if (n >= 1000000) return (n / 1000000).toFixed(1) + "M"
    if (n >= 1000) return (n / 1000).toFixed(0) + "k"
    return String(n)
}

function levelColor(pct) {
    if (pct === null) return "#585b70" // Catppuccin Mocha "surface2" - unknown/no data
    if (pct < 70) return "#74c7ec"       // sapphire - normal usage (Antigravity/Google blue family)
    if (pct < 90) return "#f9e2af"       // yellow - getting up there
    return "#f38ba8"                     // red - nearly capped
}
