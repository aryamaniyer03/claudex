import AppKit
import SwiftUI
@preconcurrency import SwiftTerm

@MainActor
final class TerminalSession: ObservableObject, Identifiable {
    let id: UUID
    @Published var name: String
    @Published var currentDirectory: String
    @Published var isRunning: Bool = true
    /// When true, terminal title updates won't overwrite the name.
    @Published var hasCustomName: Bool = false
    /// True while waiting for an initial command (e.g. claude --resume) to load.
    @Published var isLoadingCommand: Bool = false
    /// The Claude session ID this terminal was resumed with, for duplicate detection.
    let resumeSessionID: String?

    private var terminalView: LocalProcessTerminalView?
    private let shellPath: String
    private let initialDirectory: String
    private let initialCommand: String?
    private var delegate: SessionDelegate?
    private nonisolated(unsafe) var _shellPid: pid_t = 0
    private let fontSizeOverride: CGFloat
    private let fontNameOverride: String

    /// tmux session name derived from this session's UUID — stable across restarts.
    var tmuxSessionName: String {
        "th-" + id.uuidString.prefix(8).lowercased()
    }

    init(name: String, directory: String, fontSize: CGFloat = Theme.defaultFontSize, fontName: String = "Menlo", id: UUID = UUID(), initialCommand: String? = nil) {
        self.id = id
        self.name = name
        self.initialDirectory = directory
        self.currentDirectory = directory
        self.shellPath = ShellUtility.defaultShell()
        self.fontSizeOverride = fontSize
        self.fontNameOverride = fontName
        self.initialCommand = initialCommand
        self.isLoadingCommand = initialCommand != nil

        // Extract resume session ID for duplicate detection
        if let cmd = initialCommand, cmd.contains("--resume") {
            let parts = cmd.split(separator: " ")
            if let idx = parts.firstIndex(of: "--resume"), idx + 1 < parts.count {
                self.resumeSessionID = String(parts[idx + 1])
            } else {
                self.resumeSessionID = nil
            }
        } else {
            self.resumeSessionID = nil
        }
    }

    /// Lazily creates and returns the terminal view. Never call from SwiftUI body.
    func getOrCreateTerminalView() -> LocalProcessTerminalView {
        if let existing = terminalView {
            return existing
        }

        let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        // Configure appearance — match Claude.ai dark theme
        view.nativeBackgroundColor = Theme.termBgNS
        view.nativeForegroundColor = NSColor(srgbRed: 0xEC/255.0, green: 0xEC/255.0, blue: 0xEA/255.0, alpha: 1.0)
        view.caretColor = NSColor(srgbRed: 0xD9/255.0, green: 0x78/255.0, blue: 0x57/255.0, alpha: 1.0)

        // Disable mouse reporting so SwiftTerm handles text selection locally.
        // Scroll is handled separately via SGR escape sequences sent directly.
        view.allowMouseReporting = false

        if let font = NSFont(name: fontNameOverride, size: fontSizeOverride) ?? NSFont(name: "Menlo", size: fontSizeOverride) {
            view.font = font
        }

        // Set up delegate
        let sessionDelegate = SessionDelegate(session: self)
        view.processDelegate = sessionDelegate
        self.delegate = sessionDelegate

        // Build clean environment
        let env = ProcessInfo.processInfo.environment
        let stripPrefixes = ["TERM", "CLAUDECODE", "CLAUDE_CODE", "CLAUDE_"]
        var envPairs = env
            .filter { pair in !stripPrefixes.contains(where: { pair.key.hasPrefix($0) }) }
            .map { "\($0.key)=\($0.value)" }
        envPairs.append("TERM=xterm-256color")
        // Ensure UTF-8 locale so Claude Code renders Unicode symbols correctly
        if !envPairs.contains(where: { $0.hasPrefix("LANG=") }) {
            envPairs.append("LANG=en_US.UTF-8")
        }
        if !envPairs.contains(where: { $0.hasPrefix("LC_ALL=") }) {
            envPairs.append("LC_ALL=en_US.UTF-8")
        }

        // Launch via tmux if available — enables session persistence across app restarts
        if let tmuxPath = ShellUtility.findTmux() {
            let configPath = ShellUtility.ensureTmuxConfig()
            let sessionName = tmuxSessionName

            // `new-session -A` creates a new session OR attaches to an existing one.
            // On first launch: creates tmux session with shell at initialDirectory.
            // On relaunch: reattaches to the running tmux session (full state preserved).
            view.startProcess(
                executable: tmuxPath,
                args: [
                    "-L", ShellUtility.tmuxSocket,
                    "-f", configPath,
                    "new-session", "-A",
                    "-s", sessionName,
                    "-c", initialDirectory,
                ],
                environment: envPairs,
                execName: "tmux"
            )
        } else {
            // Fallback: direct shell (no persistence)
            view.startProcess(
                executable: shellPath,
                args: ["-l"],
                environment: envPairs,
                execName: "-" + (shellPath as NSString).lastPathComponent,
                currentDirectory: initialDirectory
            )
        }

        self.terminalView = view
        self._shellPid = view.process.shellPid

        // If there's an initial command (e.g. "claude --resume"), send it after shell is ready
        // then poll the terminal buffer to clear loading state when claude has started
        if let cmd = initialCommand {
            let capturedView = view
            let capturedSelf = self
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                capturedView.send(txt: cmd + "\r")
                // Poll terminal buffer — once we see enough output, claude has loaded
                capturedSelf.pollForCommandReady(view: capturedView)
            }
        }

        // Auto-generate a title after the session has some output
        let capturedSelf = self
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            capturedSelf.requestAutoTitle()
        }

        return view
    }

    /// Poll the terminal buffer until the command has produced output, then clear loading state.
    private func pollForCommandReady(view: LocalProcessTerminalView, attempt: Int = 0) {
        // Max 30 attempts × 500ms = 15 seconds timeout
        guard attempt < 30, isLoadingCommand else {
            isLoadingCommand = false
            return
        }

        let terminal = view.getTerminal()
        var lines = 0
        for row in 0..<terminal.rows {
            guard let line = terminal.getLine(row: row) else { continue }
            let text = line.translateToString().trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { lines += 1 }
        }

        // Claude Code typically shows several lines once loaded (banner, context, prompt)
        // Wait for at least 5 non-empty lines beyond the initial shell prompt + command
        if lines >= 5 {
            isLoadingCommand = false
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.pollForCommandReady(view: view, attempt: attempt + 1)
            }
        }
    }

    /// Whether we've already requested an auto-title from the LLM.
    private var autoTitleRequested = false

    /// Send text to the terminal (used for pasting file paths on drop)
    func sendText(_ text: String) {
        terminalView?.send(txt: text)
    }

    /// Make this session's terminal view first responder.
    func focus() {
        guard let tv = terminalView, let win = tv.window else { return }
        win.makeFirstResponder(tv)
    }

    /// Try to auto-generate a session title from terminal buffer content.
    /// Called once after enough output accumulates (~5s after first output).
    func requestAutoTitle() {
        guard !autoTitleRequested, !hasCustomName else { return }
        autoTitleRequested = true

        guard let tv = terminalView else { return }
        let terminal = tv.getTerminal()
        let data = terminal.getBufferAsData()
        guard let text = String(data: data, encoding: .utf8), text.count > 50 else {
            autoTitleRequested = false // retry later
            return
        }

        Task {
            if let title = await LLMService.generateTitle(from: text) {
                await MainActor.run {
                    if !self.hasCustomName {
                        self.name = title
                    }
                }
            }
        }
    }

    /// Force tmux/shell to redraw by sending SIGWINCH (window-changed signal).
    /// Call after the terminal view is laid out to fix reattach rendering.
    func forceRedraw() {
        if _shellPid > 0 {
            kill(_shellPid, SIGWINCH)
        }
    }

    /// Update the terminal font (for font size changes)
    func updateFont(_ font: NSFont) {
        terminalView?.font = font
    }

    /// Explicitly close and destroy this session (user pressed ⌘W or clicked Close).
    /// Kills the tmux session so it doesn't linger.
    func terminate() {
        // Kill the tmux session (destroys the shell inside it)
        ShellUtility.killTmuxSession(tmuxSessionName)

        // Also SIGHUP the local tmux client process
        if _shellPid > 0 {
            kill(_shellPid, SIGHUP)
            _shellPid = 0
        }
        isRunning = false
    }

    /// On deinit (app quit), just SIGHUP the tmux client — this detaches,
    /// leaving the tmux session alive for reattach on next launch.
    deinit {
        if _shellPid > 0 {
            kill(_shellPid, SIGHUP)
        }
    }
}

// MARK: - Process Delegate

@MainActor
private final class SessionDelegate: NSObject, LocalProcessTerminalViewDelegate {
    weak var session: TerminalSession?

    init(session: TerminalSession) {
        self.session = session
    }

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // Terminal handles resize internally
    }

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor [weak self] in
            guard let session = self?.session else { return }
            if !title.isEmpty && !session.hasCustomName {
                session.name = title
            }
        }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        Task { @MainActor [weak self] in
            guard let session = self?.session, let directory else { return }
            session.currentDirectory = directory
        }
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor [weak self] in
            guard let session = self?.session else { return }
            session.isRunning = false
        }
    }
}
