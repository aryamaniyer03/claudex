import Foundation

/// Usage data from Claude's API.
struct ClaudeUsage {
    var sessionPercentage: Double
    var sessionResetTime: Date

    var weeklyPercentage: Double
    var weeklyResetTime: Date

    var lastUpdated: Date

    static let empty = ClaudeUsage(
        sessionPercentage: 0,
        sessionResetTime: Date(),
        weeklyPercentage: 0,
        weeklyResetTime: Date(),
        lastUpdated: Date()
    )

    /// e.g. "Resets in 1 hr 37 min (18:29)"
    func sessionResetLabel() -> String {
        formatResetLabel(resetTime: sessionResetTime)
    }

    func weeklyResetLabel() -> String {
        formatResetLabel(resetTime: weeklyResetTime)
    }

    private func formatResetLabel(resetTime: Date) -> String {
        let now = Date()
        guard resetTime > now else { return "Reset" }

        let diff = resetTime.timeIntervalSince(now)
        let hours = Int(diff) / 3600
        let minutes = (Int(diff) % 3600) / 60

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        let timeStr = timeFmt.string(from: resetTime)

        if hours > 24 {
            let dayFmt = DateFormatter()
            dayFmt.dateFormat = "EEE, HH:mm"
            return "Resets \(dayFmt.string(from: resetTime))"
        } else if hours > 0 {
            return "Resets in \(hours) hr \(minutes) min (\(timeStr))"
        } else {
            return "Resets in \(minutes) min (\(timeStr))"
        }
    }
}
