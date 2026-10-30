.pragma library

// Reads usage data from local files for the Cindy Chats widget.
// No network access, ever.
//
// Sources:
//   1. ~/.claude/plasma-usage-status.json   - Claude Code statusLine hook
//   2. ~/.claude.json  -> cachedUsageUtilization - Claude Code's own cached quota
//   3. ~/.config/Claude/plan-usage-history.json - Claude desktop app cache
//   4. ~/.gemini/antigravity-cli/plasma-agy-status.json - antigravity-cli hook
//   5. Cindy DB account_usage_snapshots - Claude limits seen by Cindy

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
        // Claude
        sessionPct: null,        // 5-hour
        sessionResetsAt: null,
        weeklyPct: null,         // 7-day
        weeklyResetsAt: null,
        contextPct: null,
        contextSize: null,
        costUsd: null,
        durationMs: null,
        model: "",
        effort: "",
        project: "",
        // Antigravity (agy)
        agySessionPct: null,     // gemini-weekly
        agySessionResetsAt: null,
        agyWeeklyPct: null,      // 3p-weekly
        agyWeeklyResetsAt: null,
        agyContextPct: null,
        agyContextSize: null,
        agyModel: "",
        agyEffort: "",
        agyProject: "",
        agyPlanTier: "",
        agyAgentState: "",
        receivedAt: null,
        source: "none"
    }
}

function fromHookPayload(text) {
    var data
    try {
        data = JSON.parse(text)
    } catch (e) {
        return null
    }
    if (!data || typeof data !== "object") return null

    var rl = data.rate_limits || {}
    var five = rl.five_hour || {}
    var seven = rl.seven_day || {}
    if (five.used_percentage === undefined && seven.used_percentage === undefined) {
        return null
    }

    var now = Date.now() / 1000
    var fiveReset = (five.resets_at !== undefined) ? five.resets_at : now
    var sevenReset = (seven.resets_at !== undefined) ? seven.resets_at : now
    var fivePct = (five.used_percentage !== undefined)
        ? (fiveReset < now ? 0 : clampPct(five.used_percentage)) : null
    var sevenPct = (seven.used_percentage !== undefined)
        ? (sevenReset < now ? 0 : clampPct(seven.used_percentage)) : null

    var ctx = data.context_window || {}
    var cost = data.cost || {}
    var project = (data.workspace || {}).project_dir || ""

    var snap = emptySnapshot()
    snap.available = true
    snap.sessionPct = fivePct
    snap.sessionResetsAt = fiveReset
    snap.weeklyPct = sevenPct
    snap.weeklyResetsAt = sevenReset
    snap.contextPct = (ctx.used_percentage !== undefined) ? clampPct(ctx.used_percentage) : null
    snap.contextSize = ctx.context_window_size || null
    snap.costUsd = (cost.total_cost_usd !== undefined) ? cost.total_cost_usd : null
    snap.durationMs = (cost.total_duration_ms !== undefined) ? cost.total_duration_ms : null
    snap.model = (data.model || {}).display_name || ""
    snap.effort = (data.effort || {}).level || ""
    snap.project = project ? project.split("/").pop() : ""
    snap.receivedAt = (data._received_at_ts !== undefined) ? data._received_at_ts : now
    snap.source = "hook"
    return snap
}

function fromAgyPayload(text) {
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
    snap.agySessionPct = usedPctFromRemainingFraction(gem.remaining_fraction)
    snap.agySessionResetsAt = gem.reset_time ? isoToTs(gem.reset_time) : null
    snap.agyWeeklyPct = usedPctFromRemainingFraction(thirdParty.remaining_fraction)
    snap.agyWeeklyResetsAt = thirdParty.reset_time ? isoToTs(thirdParty.reset_time) : null
    snap.agyContextPct = (ctx.used_percentage !== undefined) ? clampPct(ctx.used_percentage) : null
    snap.agyContextSize = ctx.context_window_size || null
    snap.agyModel = model.display_name || ""
    snap.agyEffort = model.effort || ""
    snap.agyProject = workspace.project_dir ? String(workspace.project_dir).split("/").pop() : ""
    snap.agyPlanTier = data.plan_tier || ""
    snap.agyAgentState = data.agent_state || ""
    snap.receivedAt = (data._received_at_ts !== undefined) ? data._received_at_ts : (Date.now() / 1000)
    snap.source = "hook"
    return snap
}

function usedPctFromRemainingFraction(remain) {
    if (remain === undefined || remain === null) return null
    var n = parseFloat(remain)
    if (isNaN(n)) return null
    return clampPct((1 - n) * 100)
}

// Cindy keeps the latest Claude rate limits in its SQLite DB:
//   account_usage_snapshots(agent_kind = 'claude-code').snapshot
// `text` is `sqlite3 -json` output: [{"snapshot": "<json string>"}].
// resetsAt is in seconds, updatedAt in milliseconds.
function fromCindyDb(text) {
    var rows
    try {
        rows = JSON.parse(text)
    } catch (e) {
        return null
    }
    if (!Array.isArray(rows) || rows.length === 0) return null

    var data
    try {
        data = JSON.parse(rows[0].snapshot)
    } catch (e) {
        return null
    }
    if (!data || typeof data !== "object") return null

    var five = data.fiveHour || {}
    var seven = data.sevenDay || {}
    if (five.utilization === undefined && seven.utilization === undefined) return null

    var now = Date.now() / 1000
    var fiveReset = (five.resetsAt !== undefined) ? five.resetsAt : null
    var sevenReset = (seven.resetsAt !== undefined) ? seven.resetsAt : null

    var snap = emptySnapshot()
    snap.available = true
    snap.sessionPct = (five.utilization !== undefined)
        ? ((fiveReset !== null && fiveReset < now) ? 0 : clampPct(five.utilization)) : null
    snap.sessionResetsAt = fiveReset
    snap.weeklyPct = (seven.utilization !== undefined)
        ? ((sevenReset !== null && sevenReset < now) ? 0 : clampPct(seven.utilization)) : null
    snap.weeklyResetsAt = sevenReset
    snap.receivedAt = data.updatedAt ? data.updatedAt / 1000 : now
    snap.source = "cindy"
    return snap
}

function fromClaudeJson(text) {
    var data
    try {
        data = JSON.parse(text)
    } catch (e) {
        return null
    }
    if (!data || typeof data !== "object") return null

    var cached = data.cachedUsageUtilization
    if (!cached || cached.fetchedAtMs === undefined) return null

    var util = cached.utilization || {}
    var five = util.five_hour || {}
    var seven = util.seven_day || {}
    if (five.utilization === undefined && seven.utilization === undefined) return null

    var now = Date.now() / 1000
    var fiveReset = five.resets_at ? isoToTs(five.resets_at) : now
    var sevenReset = seven.resets_at ? isoToTs(seven.resets_at) : now
    var fivePct = (five.utilization !== undefined)
        ? (fiveReset < now ? 0 : clampPct(five.utilization)) : null
    var sevenPct = (seven.utilization !== undefined)
        ? (sevenReset < now ? 0 : clampPct(seven.utilization)) : null

    var snap = emptySnapshot()
    snap.available = true
    snap.sessionPct = fivePct
    snap.sessionResetsAt = fiveReset
    snap.weeklyPct = sevenPct
    snap.weeklyResetsAt = sevenReset
    snap.receivedAt = cached.fetchedAtMs / 1000
    snap.source = "claude-json"
    return snap
}

function fromPlanUsageHistory(text) {
    var data
    try {
        data = JSON.parse(text)
    } catch (e) {
        return null
    }
    if (!data || !Array.isArray(data.samples) || data.samples.length === 0) return null

    var last = data.samples[data.samples.length - 1]
    var u = last.u || {}
    if (u.fh === undefined && u.sd === undefined) return null

    var snap = emptySnapshot()
    snap.available = true
    snap.sessionPct = (u.fh !== undefined) ? clampPct(u.fh) : null
    snap.weeklyPct = (u.sd !== undefined) ? clampPct(u.sd) : null
    snap.sessionResetsAt = null
    snap.weeklyResetsAt = null
    snap.receivedAt = last.t ? (last.t / 1000) : (Date.now() / 1000)
    snap.source = "app-cache"
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
    if (pct === null) return "#585b70"
    if (pct < 70) return "#fab387"
    if (pct < 90) return "#f9e2af"
    return "#f38ba8"
}

function weeklyLevelColor(pct) {
    if (pct === null) return "#585b70"
    if (pct < 70) return "#b4befe"
    if (pct < 90) return "#f9e2af"
    return "#f38ba8"
}

function agyLevelColor(pct) {
    if (pct === null) return "#585b70"
    if (pct < 70) return "#74c7ec"
    if (pct < 90) return "#f9e2af"
    return "#f38ba8"
}

function agyWeeklyLevelColor(pct) {
    if (pct === null) return "#585b70"
    if (pct < 70) return "#89b4fa"
    if (pct < 90) return "#f9e2af"
    return "#f38ba8"
}