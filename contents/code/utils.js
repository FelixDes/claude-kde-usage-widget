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
