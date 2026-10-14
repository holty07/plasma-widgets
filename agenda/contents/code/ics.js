.pragma library

// ── Timezone offset table ─────────────────────────────────────────────────
// Returns UTC offset in minutes for a given IANA timezone name.
// Covers Australian, SE Asian, and common international timezones.
// DST: Australian timezones observe DST (AEDT/AEST). We determine which
// applies by checking if the date falls in the Australian DST window
// (first Sunday in October → first Sunday in April).
function getOffsetMinutes(ianaName, date) {
    if (!ianaName || !date) return 0;
    var tz = ianaName.toLowerCase().replace(/_/g, " ");

    // Australian DST check — DST is UTC+1 on top of standard
    // DST period: first Sun in Oct to first Sun in Apr (Southern Hemisphere summer)
    function isAustralianDST(d) {
        var year = d.getUTCFullYear();
        var month = d.getUTCMonth(); // 0-indexed

        // Find first Sunday in October (month 9)
        function firstSunday(y, m) {
            var d = new Date(Date.UTC(y, m, 1));
            while (d.getUTCDay() !== 0) d = new Date(d.getTime() + 86400000);
            return d;
        }

        var dstStart = firstSunday(year, 9);   // First Sun Oct
        var dstEnd   = firstSunday(year, 3);   // First Sun Apr

        // DST is active Oct → Dec, and Jan → Apr
        if (month >= 9) return d >= dstStart;           // Oct–Dec
        if (month <= 3) return d < dstEnd;              // Jan–Apr
        return false;                                    // May–Sep: standard time
    }

    var dst = isAustralianDST(date);

    var offsets = {
        // Australia
        "australia/sydney":    dst ? 660 : 600,
        "australia/melbourne": dst ? 660 : 600,
        "australia/canberra":  dst ? 660 : 600,
        "australia/hobart":    dst ? 660 : 600,
        "australia/brisbane":  600,  // Queensland — no DST
        "australia/lindeman":  600,
        "australia/adelaide":  dst ? 630 : 570,
        "australia/broken hill": dst ? 630 : 570,
        "australia/darwin":    570,  // NT — no DST
        "australia/perth":     480,
        "australia/eucla":     525,
        "australia/lord howe": dst ? 660 : 630,

        // SE Asia / Pacific
        "asia/bangkok":        420,
        "asia/ho chi minh":    420,
        "asia/saigon":         420,
        "asia/jakarta":        420,
        "asia/phnom penh":     420,
        "asia/vientiane":      420,
        "asia/rangoon":        390,
        "asia/yangon":         390,
        "asia/kuala lumpur":   480,
        "asia/singapore":      480,
        "asia/manila":         480,
        "asia/taipei":         480,
        "asia/hong kong":      480,
        "asia/shanghai":       480,
        "asia/tokyo":          540,
        "asia/seoul":          540,
        "asia/kolkata":        330,
        "asia/calcutta":       330,
        "asia/colombo":        330,
        "asia/kathmandu":      345,
        "asia/dhaka":          360,
        "asia/almaty":         360,
        "asia/dubai":          240,
        "asia/riyadh":         180,
        "asia/jerusalem":      180,  // Approximation — Israel DST varies
        "asia/beirut":         180,

        // Europe
        "europe/london":       0,    // Approximation — ignores BST
        "europe/paris":        60,   // Approximation — ignores CEST
        "europe/berlin":       60,
        "europe/amsterdam":    60,
        "europe/rome":         60,
        "europe/madrid":       60,
        "europe/zurich":       60,

        // Americas
        "america/new york":    -300, // Approximation — ignores EDT
        "america/los angeles": -480,
        "america/chicago":     -360,
        "america/denver":      -420,
        "america/phoenix":     -420, // Arizona — no DST
        "america/toronto":     -300,
        "america/vancouver":   -480,

        // UTC variants
        "utc":                 0,
        "gmt":                 0,
    };

    var offset = offsets[tz];
    if (offset !== undefined) return offset;

    // Try partial match for common prefixes
    for (var key in offsets) {
        if (tz.indexOf(key) !== -1 || key.indexOf(tz) !== -1) {
            return offsets[key];
        }
    }

    // Unknown timezone — return 0 and let the raw value show in debug
    console.log("Unknown timezone: " + ianaName);
    return 0;
}

// Parse a full DTSTART/DTEND line into a JS Date.
function parseICSLine(line) {
    if (!line) return null;
    var colonIdx = line.indexOf(":");
    if (colonIdx === -1) return null;

    var paramStr = line.substring(0, colonIdx);
    var raw = line.substring(colonIdx + 1).trim();

    var allDay = paramStr.toUpperCase().indexOf("VALUE=DATE") !== -1;
    var tzMatch = line.match(/TZID=([^;:]+)/i);
    var tzid = tzMatch ? tzMatch[1].trim() : null;

    if (raw.length === 8) {
        return {
            date: new Date(
                parseInt(raw.substr(0, 4)),
                parseInt(raw.substr(4, 2)) - 1,
                parseInt(raw.substr(6, 2)),
                0, 0, 0
            ),
            allDay: true
        };
    } else if (raw.length >= 15) {
        var y  = parseInt(raw.substr(0, 4));
        var mo = parseInt(raw.substr(4, 2)) - 1;
        var d  = parseInt(raw.substr(6, 2));
        var h  = parseInt(raw.substr(9, 2));
        var mi = parseInt(raw.substr(11, 2));
        var s  = parseInt(raw.substr(13, 2));
        var isUtc = raw.charAt(15) === "Z";

        var utcMs;
        if (isUtc) {
            utcMs = Date.UTC(y, mo, d, h, mi, s);
        } else if (tzid) {
            // Convert wall-clock time in named tz to UTC
            var wallMs = Date.UTC(y, mo, d, h, mi, s);
            var offsetMins = getOffsetMinutes(tzid, new Date(wallMs));
            utcMs = wallMs - offsetMins * 60000;
        } else {
            // Floating — treat as local
            utcMs = new Date(y, mo, d, h, mi, s).getTime();
        }

        return { date: new Date(utcMs), allDay: allDay };
    }
    return null;
}

// ── RRULE expander ────────────────────────────────────────────────────────
function expandRRule(rrule, dtstart, rangeStart, rangeEnd) {
    var occurrences = [];
    if (!rrule || !dtstart) return occurrences;

    var params = {};
    rrule.replace(/^RRULE:/i, "").split(";").forEach(function(part) {
        var kv = part.split("=");
        if (kv.length === 2) params[kv[0].toUpperCase()] = kv[1].toUpperCase();
    });

    var freq     = params["FREQ"] || "";
    var interval = parseInt(params["INTERVAL"] || "1");
    var count    = params["COUNT"] ? parseInt(params["COUNT"]) : null;
    var until    = null;
    if (params["UNTIL"]) {
        var u = params["UNTIL"];
        until = new Date(Date.UTC(
            parseInt(u.substr(0,4)), parseInt(u.substr(4,2))-1, parseInt(u.substr(6,2)),
            u.length > 8 ? parseInt(u.substr(9,2)) : 0,
            u.length > 11 ? parseInt(u.substr(11,2)) : 0, 0
        ));
    }

    var byDay = params["BYDAY"] ? params["BYDAY"].split(",") : null;

    var current = new Date(dtstart.getTime());
    var n = 0;
    var maxIter = 1000;

    while (maxIter-- > 0) {
        if (until && current > until) break;
        if (count !== null && n >= count) break;
        if (current > rangeEnd) break;

        if (current >= rangeStart && current <= rangeEnd) {
            occurrences.push(new Date(current.getTime()));
        }

        if (freq === "DAILY") {
            current = new Date(current.getTime() + interval * 86400000);
        } else if (freq === "WEEKLY") {
            if (byDay && byDay.length > 1) {
                var stepped = false;
                for (var dd = 1; dd <= 7 * interval; dd++) {
                    var cand = new Date(current.getTime() + dd * 86400000);
                    var dowStr = ["SU","MO","TU","WE","TH","FR","SA"][cand.getDay()];
                    if (byDay.indexOf(dowStr) !== -1) {
                        var weeksSinceStart = Math.floor((cand.getTime() - dtstart.getTime()) / (7 * interval * 86400000));
                        var currentWeek    = Math.floor((current.getTime() - dtstart.getTime()) / (7 * interval * 86400000));
                        if (weeksSinceStart >= currentWeek) {
                            current = cand;
                            stepped = true;
                            break;
                        }
                    }
                }
                if (!stepped) current = new Date(current.getTime() + 7 * interval * 86400000);
            } else {
                current = new Date(current.getTime() + 7 * interval * 86400000);
            }
        } else if (freq === "MONTHLY") {
            current = new Date(current.getFullYear(), current.getMonth() + interval,
                               current.getDate(), current.getHours(), current.getMinutes(), current.getSeconds());
        } else if (freq === "YEARLY") {
            current = new Date(current.getFullYear() + interval, current.getMonth(),
                               current.getDate(), current.getHours(), current.getMinutes(), current.getSeconds());
        } else {
            break;
        }
        n++;
    }

    return occurrences;
}

// ── Display helpers ───────────────────────────────────────────────────────
function relTime(diffMins) {
    if (diffMins < 60) return diffMins + "m";
    var hours = Math.floor(diffMins / 60);
    var mins = diffMins % 60;
    if (mins === 0) return hours + "h";
    return hours + "h " + mins + "m";
}

function endsIn(startDate, endDate) {
    if (!endDate) return "";
    var nowMs = Date.now();
    if (startDate && startDate.getTime() > nowMs) {
        var diffMins = Math.floor((startDate.getTime() - nowMs) / 60000);
        if (diffMins <= 0) return "starting now";
        return "starts in " + relTime(diffMins);
    } else {
        var diffMs = endDate.getTime() - nowMs;
        if (diffMs <= 0) return "ended";
        var diffMins = Math.floor(diffMs / 60000);
        if (diffMins <= 0) return "ending now";
        return "ends in " + relTime(diffMins);
    }
}

function formatTime(date, isAllDay) {
    if (isAllDay) return "All day";
    var h = date.getHours();
    var m = date.getMinutes();
    var ampm = h >= 12 ? "PM" : "AM";
    h = h % 12;
    if (h === 0) h = 12;
    var ms = m < 10 ? "0" + m : "" + m;
    return h + ":" + ms + " " + ampm;
}

// ── Main ICS parser ───────────────────────────────────────────────────────
function parseICS(icsText) {
    var events = [];
    if (!icsText || icsText.length === 0) return events;

    var unfolded = icsText.replace(/\r\n[ \t]/g, "").replace(/\n[ \t]/g, "");
    var lines = unfolded.split(/\r?\n/);

    var now = new Date();
    var todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0);
    var todayEnd   = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59);

    var inEvent = false;
    var current = {};

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();

        if (line === "BEGIN:VEVENT") {
            inEvent = true;
            current = {
                summary: "", location: "",
                dtstart: null, dtend: null,
                allDay: false, rrule: null,
                exdates: []
            };
            continue;
        }

        if (line === "END:VEVENT") {
            inEvent = false;

            if (current.dtstart) {
                var duration = current.dtend
                    ? (current.dtend.getTime() - current.dtstart.getTime())
                    : 0;

                if (current.rrule) {
                    var lookback = new Date(todayStart.getTime() - 365 * 86400000);
                    var occurrences = expandRRule(current.rrule, current.dtstart, lookback, todayEnd);
                    for (var oi = 0; oi < occurrences.length; oi++) {
                        var occStart = occurrences[oi];
                        var occEnd   = new Date(occStart.getTime() + duration);

                        var excluded = false;
                        for (var ei = 0; ei < current.exdates.length; ei++) {
                            if (Math.abs(occStart.getTime() - current.exdates[ei].getTime()) < 86400000) {
                                excluded = true; break;
                            }
                        }
                        if (excluded) continue;

                        var startsToday = occStart >= todayStart && occStart <= todayEnd;
                        var spansToday  = occStart < todayStart && occEnd > todayStart;
                        if ((startsToday || spansToday) && (current.allDay || occEnd > now)) {
                            events.push({
                                summary:  current.summary || "Untitled",
                                start:    occStart,
                                end:      occEnd,
                                allDay:   current.allDay,
                                location: current.location,
                                startStr: formatTime(occStart, current.allDay)
                            });
                        }
                    }
                } else {
                    var start = current.dtstart;
                    var end   = current.dtend || start;
                    var startsToday = start >= todayStart && start <= todayEnd;
                    var spansToday  = start < todayStart && end > todayStart;
                    if ((startsToday || spansToday) && (current.allDay || end > now)) {
                        events.push({
                            summary:  current.summary || "Untitled",
                            start:    start,
                            end:      end,
                            allDay:   current.allDay,
                            location: current.location,
                            startStr: formatTime(start, current.allDay)
                        });
                    }
                }
            }
            current = {};
            continue;
        }

        if (!inEvent) continue;

        var upper = line.toUpperCase();
        if (upper.startsWith("SUMMARY:")) {
            current.summary = line.substring(8);
        } else if (upper.startsWith("LOCATION:")) {
            current.location = line.substring(9);
        } else if (upper.startsWith("RRULE:")) {
            current.rrule = line;
        } else if (upper.startsWith("EXDATE")) {
            var exResult = parseICSLine(line);
            if (exResult) current.exdates.push(exResult.date);
        } else if (upper.startsWith("DTSTART")) {
            var result = parseICSLine(line);
            if (result) {
                current.dtstart = result.date;
                current.allDay  = result.allDay;
            }
        } else if (upper.startsWith("DTEND")) {
            var result = parseICSLine(line);
            if (result) current.dtend = result.date;
        }
    }

    events.sort(function(a, b) {
        if (a.allDay && !b.allDay) return -1;
        if (!a.allDay && b.allDay) return 1;
        return a.start - b.start;
    });

    return events;
}
