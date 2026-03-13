import Foundation

struct DiscoveredTerminal: Identifiable {
    let id: String          // TTY path, unique per tab
    let tty: String
    let pid: pid_t
    let shellName: String
    let cwd: String
    let windowID: Int       // <= 0 means the original window cannot be targeted for closing
    let tabIndex: Int
    let runningCommand: String?  // e.g. "claude --dangerously-skip-permissions"
}

/// Discovers running terminal sessions via process inspection — no AppleScript needed.
/// All methods are synchronous and perform blocking I/O — call from a background thread.
enum TerminalDiscovery {

    // MARK: - Public

    /// Find all terminal sessions by scanning for shell processes on TTYs.
    /// Detects sessions regardless of which terminal app is running (Terminal.app, iTerm2, etc).
    static func discoverTerminalApp() -> [DiscoveredTerminal] {
        // Find Claudex's own tmux TTYs so we can exclude them
        let ownTTYs = claudexTTYs()

        // Find all shell processes on TTYs
        guard let output = runCommand("/bin/ps", args: ["-e", "-o", "pid=,tty=,stat=,comm="]) else {
            return []
        }

        struct ShellInfo {
            let pid: pid_t
            let tty: String
            let isForeground: Bool
            let comm: String
        }

        var shellsByTTY: [String: [ShellInfo]] = [:]
        var ttysWithLogin: Set<String> = []

        for line in output.split(separator: "\n") {
            let cols = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard cols.count >= 4 else { continue }

            let pid = pid_t(cols[0]) ?? 0
            let tty = cols[1]
            let stat = cols[2]
            let comm = URL(fileURLWithPath: cols[3]).lastPathComponent

            guard tty.hasPrefix("ttys") else { continue }
            guard !ownTTYs.contains(tty) else { continue }

            // Track TTYs that have a login process (real terminal sessions)
            if comm == "login" {
                ttysWithLogin.insert(tty)
            }

            if knownShells.contains(comm) {
                let info = ShellInfo(pid: pid, tty: tty, isForeground: stat.contains("+"), comm: comm)
                shellsByTTY[tty, default: []].append(info)
            }
        }

        // Only include TTYs that have a login process — filters out orphaned/tmux shells
        shellsByTTY = shellsByTTY.filter { ttysWithLogin.contains($0.key) }

        // Also find foreground commands per TTY (claude, node, python, etc.)
        var fgCommandByTTY: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let cols = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard cols.count >= 4 else { continue }
            let tty = cols[1]
            let stat = cols[2]
            let comm = URL(fileURLWithPath: cols[3]).lastPathComponent
            guard tty.hasPrefix("ttys"), stat.contains("+"), !knownShells.contains(comm) else { continue }
            // Keep the most interesting foreground command (prefer "claude" over "caffeinate" etc.)
            if comm == "claude" || comm == "Claude" {
                fgCommandByTTY[tty] = comm
            } else if fgCommandByTTY[tty] == nil && comm != "login" && comm != "caffeinate" {
                fgCommandByTTY[tty] = comm
            }
        }

        // Also get full command lines for claude processes to capture flags
        let fullCommands = claudeCommandLines()

        var results: [DiscoveredTerminal] = []
        var index = 0

        for (tty, shells) in shellsByTTY.sorted(by: { $0.key < $1.key }) {
            guard let shell = shells.first(where: { $0.isForeground }) ?? shells.first else { continue }
            guard let cwd = processCwd(pid: shell.pid) else { continue }

            // Find the running command, with full args if it's claude
            var runningCmd: String? = nil
            if let fg = fgCommandByTTY[tty] {
                if fg.lowercased() == "claude", let fullCmd = fullCommands[tty] {
                    runningCmd = fullCmd
                } else {
                    runningCmd = fg
                }
            }

            index += 1
            results.append(DiscoveredTerminal(
                id: "/dev/\(tty)",
                tty: "/dev/\(tty)",
                pid: shell.pid,
                shellName: shell.comm,
                cwd: cwd,
                windowID: 0,
                tabIndex: index,
                runningCommand: runningCmd
            ))
        }

        return results
    }

    /// Returns a map of TTY → full claude command line (e.g. "claude --dangerously-skip-permissions").
    private static func claudeCommandLines() -> [String: String] {
        guard let output = runCommand("/bin/ps", args: ["-e", "-o", "tty=,args="]) else { return [:] }
        var result: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Split into tty and the rest (args)
            guard let firstSpace = trimmed.firstIndex(of: " ") else { continue }
            let tty = String(trimmed[trimmed.startIndex..<firstSpace])
            let args = trimmed[firstSpace...].trimmingCharacters(in: .whitespaces)
            guard tty.hasPrefix("ttys") else { continue }
            // Look for claude commands
            let basename = URL(fileURLWithPath: args.components(separatedBy: " ").first ?? "").lastPathComponent
            if basename.lowercased() == "claude" {
                result[tty] = args
            }
        }
        return result
    }

    /// Returns the set of TTY names owned by Claudex's tmux sessions.
    private static func claudexTTYs() -> Set<String> {
        // List tmux clients on our socket — each shows the TTY it's attached from
        guard let output = runCommand("/usr/bin/env", args: [
            "tmux", "-L", "terminalhub", "list-panes", "-a", "-F", "#{pane_tty}"
        ]) else { return [] }

        var ttys = Set<String>()
        for line in output.split(separator: "\n") {
            let tty = line.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "/dev/", with: "")
            if !tty.isEmpty { ttys.insert(tty) }
        }
        return ttys
    }

    /// Close Terminal.app windows whose IDs are in the given set.
    static func closeTerminalAppWindows(_ windowIDs: Set<Int>) {
        guard !windowIDs.isEmpty else { return }
        // Build AppleScript list literal: {123, 456}
        let idList = windowIDs.map(String.init).joined(separator: ", ")
        let script = """
        tell application "Terminal"
            repeat with w in (reverse of (windows as list))
                if id of w is in {\(idList)} then
                    close w saving no
                end if
            end repeat
        end tell
        """
        _ = runAppleScript(script)
    }

    // MARK: - Private helpers

    private static let knownShells: Set<String> = [
        "zsh", "bash", "fish", "sh", "tcsh", "csh",
        "-zsh", "-bash", "-fish", "-sh"
    ]

    /// Return (pid, command) for the shell process on a given TTY.
    /// Prefers the foreground shell, but falls back to any shell on the TTY
    /// (e.g. when claude or another program is in the foreground).
    private static func foregroundShell(tty: String) -> (pid_t, String)? {
        guard let output = runCommand("/bin/ps", args: ["-o", "pid=,stat=,comm=", "-t", tty]) else {
            return nil
        }

        var foregroundShell: (pid_t, String)?
        var backgroundShell: (pid_t, String)?

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let cols = trimmed.split(separator: " ", maxSplits: 2).map(String.init)
            guard cols.count >= 3 else { continue }

            let pid  = pid_t(cols[0]) ?? 0
            let stat = cols[1]
            let comm = URL(fileURLWithPath: cols[2]).lastPathComponent

            guard knownShells.contains(comm) else { continue }

            if stat.contains("+") {
                foregroundShell = (pid, comm)
            } else if backgroundShell == nil {
                backgroundShell = (pid, comm)
            }
        }

        return foregroundShell ?? backgroundShell
    }

    /// Use lsof to resolve a process's current working directory.
    private static func processCwd(pid: pid_t) -> String? {
        guard let output = runCommand("/usr/sbin/lsof",
                                      args: ["-a", "-d", "cwd", "-Fn", "-p", "\(pid)"]) else {
            return nil
        }
        for line in output.split(separator: "\n") {
            if line.hasPrefix("n/") {
                return String(line.dropFirst(1))   // strip the 'n' field prefix
            }
        }
        return nil
    }

    // MARK: - Shell helpers

    private static func runCommand(_ executable: String, args: [String]) -> String? {
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            // Read BEFORE waiting — prevents deadlock when pipe buffer fills
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private static func runAppleScript(_ source: String) -> String? {
        runCommand("/usr/bin/osascript", args: ["-e", source])
    }
}
