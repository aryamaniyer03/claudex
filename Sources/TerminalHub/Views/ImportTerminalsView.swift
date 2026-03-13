import SwiftUI

struct ImportTerminalsView: View {
    @ObservedObject var sessionManager: SessionManager
    @Binding var isPresented: Bool

    @State private var discovered: [DiscoveredTerminal] = []
    @State private var selected: Set<String> = []
    @State private var isLoading = true
    @State private var closeAfterImport = true
    @State private var hoveredID: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Theme.border.frame(height: 1)
            content
            Theme.border.frame(height: 1)
            footer
        }
        .frame(width: 500, height: 400)
        .background(Theme.bg)
        .task { await loadTerminals() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import Claude Code Sessions")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Bring existing Claude Code sessions into Claudex")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textDim)
                }
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.small).scaleEffect(0.8)
                }
            }

            // Warning
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.accent)
                Text("Make sure Claude isn't actively working before importing")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.accent.opacity(0.08))
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var content: some View {
        if discovered.isEmpty && !isLoading {
            emptyContent
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(discovered) { terminal in
                        ImportRow(
                            terminal: terminal,
                            isSelected: selected.contains(terminal.id),
                            isHovered: hoveredID == terminal.id
                        )
                        .onTapGesture { toggleSelection(terminal.id) }
                        .onHover { h in hoveredID = h ? terminal.id : nil }
                    }
                }
                .padding(10)
            }
        }
    }

    private var emptyContent: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "app.dashed")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.textFaint)
            Text("No sessions found")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textMuted)
            Text("No Claude Code sessions running in Terminal.app")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textDim)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $closeAfterImport) {
                Text("Close originals")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
            }
            .toggleStyle(.checkbox)

            Spacer()

            Button("Cancel") { isPresented = false }
                .buttonStyle(SheetButtonStyle(isProminent: false))
                .keyboardShortcut(.cancelAction)

            Button("Import \(importCountLabel)") { performImport() }
                .buttonStyle(SheetButtonStyle(isProminent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(discovered.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Actions

    private func toggleSelection(_ id: String) {
        if selected.contains(id) { selected.remove(id) }
        else { selected.insert(id) }
    }

    private var importCountLabel: String {
        let c = selected.count
        if c == 0 || c == discovered.count { return "All" }
        return "(\(c))"
    }

    private func loadTerminals() async {
        isLoading = true
        let results = await Task.detached {
            TerminalDiscovery.discoverTerminalApp()
        }.value
        discovered = results
        selected = Set(results.map(\.id))
        isLoading = false
    }

    private func performImport() {
        let toImport = selected.isEmpty
            ? discovered
            : discovered.filter { selected.contains($0.id) }
        let windowIDs = Set(toImport.map(\.windowID))
        for t in toImport {
            // If Claude Code was running, resume it with --continue
            var initCommand: String? = nil
            if let cmd = t.runningCommand, cmd.lowercased().contains("claude") {
                // Replace the exact command with --continue variant
                // e.g. "claude --dangerously-skip-permissions" → "claude --continue --dangerously-skip-permissions"
                if cmd.contains("--continue") {
                    initCommand = cmd
                } else {
                    // Insert --continue after "claude"
                    initCommand = cmd.replacingOccurrences(
                        of: "claude",
                        with: "claude --continue",
                        options: [.caseInsensitive],
                        range: cmd.range(of: "claude", options: .caseInsensitive)
                    )
                }
            }
            sessionManager.createSession(
                directory: t.cwd,
                name: (t.cwd as NSString).lastPathComponent,
                initialCommand: initCommand
            )
        }
        if closeAfterImport {
            Task.detached { TerminalDiscovery.closeTerminalAppWindows(windowIDs) }
        }
        isPresented = false
    }
}

// MARK: - Import row (extracted to help the type-checker)

private struct ImportRow: View {
    let terminal: DiscoveredTerminal
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 10) {
            checkbox
            icon
            labels
            Spacer(minLength: 0)
            ttyBadge
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(rowBg)
        .contentShape(Rectangle())
    }

    private var checkbox: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 14))
            .foregroundStyle(isSelected ? Theme.accent : Theme.textDim)
    }

    private var icon: some View {
        Image(systemName: "apple.terminal")
            .font(.system(size: 13))
            .foregroundStyle(Theme.textMuted)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text((terminal.cwd as NSString).lastPathComponent)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Text(abbreviatePath(terminal.cwd))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textDim)
                .lineLimit(1)
        }
    }

    private var ttyBadge: some View {
        Text(terminal.tty.replacingOccurrences(of: "/dev/", with: ""))
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.textFaint)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Theme.surface)
            )
    }

    private var rowBg: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isSelected ? Theme.raised : (isHovered ? Theme.raised.opacity(0.5) : Color.clear))
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = ShellUtility.homeDirectory()
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }
}

// MARK: - Button style

private struct SheetButtonStyle: ButtonStyle {
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: isProminent ? .semibold : .medium))
            .foregroundStyle(isProminent ? Theme.accent : Theme.textMuted)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? Theme.selected.opacity(0.7) : Theme.surface)
            )
    }
}
