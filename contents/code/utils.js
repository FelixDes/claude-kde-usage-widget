.pragma library

// Shared status/color logic for the compact bars and the popup rows.

var CLAUDE_COLOR = "#DA7756"
var WARN_COLOR = "#E8A87C"
var WARN_THRESHOLD = 0.85

function isLimited(status) {
    return status === "limited" || status === "blocked"
}

function barColor(status, utilization, negativeColor) {
    if (isLimited(status))
        return negativeColor
    return utilization > WARN_THRESHOLD ? WARN_COLOR : CLAUDE_COLOR
}

function resetTimestampMs(resetTs) {
    if (resetTs === null || resetTs === undefined)
        return NaN

    var value = String(resetTs).trim()
    if (!value)
        return NaN

    var numeric = Number(value)
    if (isFinite(numeric)) {
        if (numeric <= 0)
            return NaN
        return numeric >= 100000000000 ? numeric : numeric * 1000
    }

    var parsed = Date.parse(value)
    return isNaN(parsed) ? NaN : parsed
}

// Date.now() alone is not a reactive QML dependency, so callers pass a
// periodically updated nowMs property.
function formatReset(resetTs, fallback, nowMs, compact) {
    var resetMs = resetTimestampMs(resetTs)
    var currentMs = Number(nowMs)
    if (!isFinite(resetMs) || !isFinite(currentMs) || currentMs <= 0)
        return fallback || ""

    var diffMs = resetMs - currentMs
    if (diffMs <= 0)
        return "now"
    if (diffMs < 60000)
        return compact ? "<1m" : "< 1 min"

    // Round up so the label never says that a reset has arrived early.
    var totalMins = Math.ceil(diffMs / 60000)
    var days = Math.floor(totalMins / 1440)
    var hours = Math.floor((totalMins % 1440) / 60)
    var mins = totalMins % 60

    if (compact) {
        if (days > 0) {
            // Minutes do not fit in the panel's day format, so round the
            // displayed hours up instead of claiming the reset is earlier.
            var totalHours = Math.ceil(totalMins / 60)
            var compactDays = Math.floor(totalHours / 24)
            var compactHours = totalHours % 24
            return compactDays + "d" + (compactHours > 0 ? " " + compactHours + "h" : "")
        }
        if (hours > 0)
            return hours + "h" + (mins > 0 ? " " + mins + "m" : "")
        return mins + "m"
    }

    var parts = []
    if (days > 0) parts.push(days + "d")
    if (hours > 0) parts.push(hours + " hr")
    if (mins > 0) parts.push(mins + " min")
    return parts.join(" ")
}

// Map a Statuspage severity (indicator or incident impact) to a theme color.
// Severities: none | minor | major | critical.
function severityColor(severity, positiveColor, neutralColor, negativeColor, disabledColor) {
    switch (severity) {
        case "none":     return positiveColor
        case "minor":    return neutralColor
        case "major":    return WARN_COLOR
        case "critical": return negativeColor
        default:         return disabledColor
    }
}

function aggregateStatusSeverity(indicator, incidents) {
    var ranks = { "none": 0, "minor": 1, "major": 2, "critical": 3 }
    var best = typeof indicator === "string" ? indicator : ""
    var bestRank = ranks[best] === undefined ? 0 : ranks[best]

    if (Array.isArray(incidents)) {
        for (var i = 0; i < incidents.length; ++i) {
            var impact = incidents[i] && typeof incidents[i].impact === "string"
                ? incidents[i].impact : ""
            var rank = ranks[impact]
            if (rank !== undefined && rank > bestRank) {
                best = impact
                bestRank = rank
            }
        }
    }
    return best
}

function parseStatusOutput(stdout, stderr) {
    var text = String(stdout || "").trim()
    if (!text) {
        var outputError = String(stderr || "").trim()
        return { "data": null, "error": outputError || "No status output" }
    }

    try {
        var parsed = JSON.parse(text)
        if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
            return { "data": null, "error": "Invalid status response" }
        if (parsed.error)
            return { "data": null, "error": String(parsed.error) }

        var indicator = typeof parsed.indicator === "string" ? parsed.indicator : ""
        if (!indicator)
            return { "data": null, "error": "Invalid status response" }

        var incidents = []
        if (Array.isArray(parsed.incidents)) {
            for (var i = 0; i < parsed.incidents.length; ++i) {
                var incident = parsed.incidents[i]
                if (!incident || typeof incident !== "object" || Array.isArray(incident))
                    continue
                incidents.push({
                    "name": typeof incident.name === "string" ? incident.name : "",
                    "impact": typeof incident.impact === "string" ? incident.impact : "",
                    "status": typeof incident.status === "string" ? incident.status : "",
                    "shortlink": typeof incident.shortlink === "string" ? incident.shortlink : ""
                })
            }
        }

        return {
            "data": {
                "indicator": indicator,
                "description": typeof parsed.description === "string" ? parsed.description : "",
                "incidents": incidents
            },
            "error": ""
        }
    } catch (e) {
        return { "data": null, "error": "Status parse error" }
    }
}
