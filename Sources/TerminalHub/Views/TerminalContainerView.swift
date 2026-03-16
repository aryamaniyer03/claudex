import AppKit
import SwiftUI
@preconcurrency import SwiftTerm

/// The raw NSViewRepresentable bridge — manages the terminal NSView lifecycle,
/// adds internal padding, and handles file drag-and-drop (inserts shell-escaped paths).
struct RawTerminalView: NSViewRepresentable {
    let session: TerminalSession
    let sessionManager: SessionManager

    private let inset: CGFloat = 8

    func makeNSView(context: Context) -> PaddedContainerView {
        let container = PaddedContainerView()
        container.session = session
        container.wantsLayer = true
        container.layer?.backgroundColor = Theme.termBgNS.cgColor
        attachTerminal(to: container)
        return container
    }

    func updateNSView(_ container: PaddedContainerView, context: Context) {
        container.session = session
        let terminalView = session.getOrCreateTerminalView()
        if terminalView.superview === container { return }
        for subview in container.subviews { subview.removeFromSuperview() }
        attachTerminal(to: container)
    }

    private func attachTerminal(to container: PaddedContainerView) {
        let terminalView = session.getOrCreateTerminalView()
        terminalView.removeFromSuperview()
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(terminalView)

        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: container.topAnchor, constant: inset),
            terminalView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: inset * -1),
            terminalView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            terminalView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: inset * -1),
        ])

        DispatchQueue.main.async {
            // Only grab focus if our window is the key window — avoids stealing
            // keyboard input from login sheets or other windows.
            if let win = terminalView.window, win.isKeyWindow {
                win.makeFirstResponder(terminalView)
            }
        }

        // After layout settles, force tmux to re-query terminal size and redraw.
        // Fixes garbled rendering when reattaching to an existing tmux session.
        let capturedSession = session
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            capturedSession.forceRedraw()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            capturedSession.forceRedraw()
        }
    }
}

/// Container NSView that accepts file drops.
final class PaddedContainerView: NSView {
    var session: TerminalSession?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        // Retry keyDown swizzle now that SwiftTerm classes are loaded
        if let mgr = SessionManager.sharedForSwizzle {
            SessionManager.installKeySwizzle(manager: mgr)
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
        if let mgr = SessionManager.sharedForSwizzle {
            SessionManager.installKeySwizzle(manager: mgr)
        }
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) else {
            return []
        }
        return .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !urls.isEmpty else {
            return false
        }

        // Build space-separated, shell-escaped paths
        let escapedPaths = urls.map { shellEscape($0.path) }.joined(separator: " ")
        session?.sendText(escapedPaths)
        return true
    }

    /// Shell-escape a path: wrap in single quotes, escape any internal single quotes.
    private func shellEscape(_ path: String) -> String {
        // If the path has no special characters, return as-is
        let needsEscape = path.contains(where: { " \t'\"\\()[]{}$&|;!?*~<>#".contains($0) })
        if !needsEscape { return path }
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}

/// Wraps the raw terminal in a styled pane with title bar, rounded corners, and border.
struct TerminalContainerView: View {
    @ObservedObject var session: TerminalSession
    @ObservedObject var sessionManager: SessionManager

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            ZStack {
                // Terminal always exists so the process runs, but hidden under the overlay
                RawTerminalView(session: session, sessionManager: sessionManager)

                // Opaque cover while loading — solid rectangle guarantees no bleed-through
                if session.isLoadingCommand {
                    Rectangle()
                        .fill(Color(nsColor: Theme.termBgNS))
                        .overlay {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .controlSize(.regular)
                                    .scaleEffect(0.8)
                                Text("Resuming session...")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.textMuted)
                                Text(session.name)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textDim)
                                    .lineLimit(1)
                            }
                        }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .padding(10)
        .background(Theme.bg)
    }

    private var titleBar: some View {
        HStack(spacing: 8) {
            // Sidebar toggle
            titleBarButton(icon: "sidebar.left") {
                sessionManager.toggleSidebar()
            }

            Image(systemName: "folder.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textDim)

            Text(session.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)

            Text(abbreviatePath(session.currentDirectory))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textDim)
                .lineLimit(1)

            Spacer()

            if session.isRunning {
                Circle()
                    .fill(Theme.green)
                    .frame(width: 6, height: 6)
            } else {
                Text("exited")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.redDim)
                    .textCase(.uppercase)
            }

            // Preview toggle — shows file count badge when hidden
            if !sessionManager.previewFiles.isEmpty {
                titleBarButton(icon: "sidebar.right") {
                    sessionManager.togglePreviewPanel()
                }
                .overlay(alignment: .topTrailing) {
                    if sessionManager.previewHidden {
                        Text("\(sessionManager.previewFiles.count)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Theme.accent))
                            .offset(x: 4, y: -4)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.surface)
    }

    private func titleBarButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textMuted)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = ShellUtility.homeDirectory()
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }
}
