import Foundation

enum ShellUtility {
    /// Returns the user's default shell path, falling back to /bin/zsh
    static func defaultShell() -> String {
        if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty {
            return shell
        }
        if let pw = getpwuid(getuid()), let shellCStr = pw.pointee.pw_shell {
            let shell = String(cString: shellCStr)
            if !shell.isEmpty { return shell }
        }
        return "/bin/zsh"
    }

    /// Returns the user's home directory
    static func homeDirectory() -> String {
        return NSHomeDirectory()
    }

    // MARK: - tmux

    /// Find tmux binary, or nil if not installed
    static func findTmux() -> String? {
        let candidates = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Path to TerminalHub's dedicated tmux config. Created on first call.
    static func ensureTmuxConfig() -> String {
        let configDir = homeDirectory() + "/.config/terminalhub"
        let configPath = configDir + "/tmux.conf"

        // Always regenerate to pick up config changes
        try? FileManager.default.createDirectory(
            atPath: configDir, withIntermediateDirectories: true)
        let config = """
        # Claudex tmux config — do not edit, regenerated automatically
        set -g status off
        set -g mouse on
        set -g history-limit 50000
        set -g default-terminal "xterm-256color"
        set -g escape-time 10
        set -g focus-events on
        # Style copy-mode to blend with Claudex dark theme (no yellow bar)
        set -g mode-style "bg=#333330,fg=#B4B0A9"
        set -g message-style "bg=#242423,fg=#7C7871"
        set -g copy-mode-match-style "bg=#333330,fg=#D97857"
        set -g copy-mode-current-match-style "bg=#333330,fg=#D97857"
        """
        try? config.write(toFile: configPath, atomically: true, encoding: .utf8)
        return configPath
    }

    /// Unique tmux socket name so we don't collide with user's own tmux.
    static let tmuxSocket = "terminalhub"

    /// Check if a tmux session exists on our socket.
    static func tmuxSessionExists(_ name: String) -> Bool {
        guard let tmux = findTmux() else { return false }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: tmux)
        proc.arguments = ["-L", tmuxSocket, "has-session", "-t", name]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Kill a tmux session on our socket.
    static func killTmuxSession(_ name: String) {
        guard let tmux = findTmux() else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: tmux)
        proc.arguments = ["-L", tmuxSocket, "kill-session", "-t", name]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
    }
}
