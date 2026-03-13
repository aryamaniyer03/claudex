import Foundation

/// A Claude Code conversation thread parsed from ~/.claude/projects/.
struct ClaudeThread: Identifiable {
    let id: String           // session UUID (file name)
    let projectDir: String   // e.g. "-Volumes-Coder-EQ--Analyst"
    let cwd: String          // actual directory path
    let slug: String?        // human-readable name like "binary-dazzling-creek"
    let firstMessage: String?
    let modifiedAt: Date

    /// Display name: slug formatted, or first message snippet, or session ID prefix.
    var displayName: String {
        if let slug = slug, !slug.isEmpty {
            return slug.replacingOccurrences(of: "-", with: " ").capitalized
        }
        if let msg = firstMessage, !msg.isEmpty {
            let clean = msg.prefix(60)
            return String(clean) + (msg.count > 60 ? "..." : "")
        }
        return String(id.prefix(8))
    }

    /// Relative time label: "2m", "3h", "1d", "2w", "1mo"
    var timeLabel: String {
        let diff = Date().timeIntervalSince(modifiedAt)
        if diff < 60 { return "now" }
        if diff < 3600 { return "\(Int(diff / 60))m" }
        if diff < 86400 { return "\(Int(diff / 3600))h" }
        if diff < 604800 { return "\(Int(diff / 86400))d" }
        if diff < 2592000 { return "\(Int(diff / 604800))w" }
        return "\(Int(diff / 2592000))mo"
    }
}

/// A project group containing threads.
struct ClaudeProject: Identifiable {
    let id: String          // projectDir
    let name: String        // human-readable project name
    let path: String        // real filesystem path
    let threads: [ClaudeThread]  // sorted by modifiedAt descending
}
