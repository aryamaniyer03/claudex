import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @ObservedObject var sessionManager: SessionManager
    @State private var hoveredID: UUID?
    @State private var editingSessionID: UUID?
    @State private var projects: [ClaudeProject] = []
    @State private var expandedProjects: Set<String> = []
    @State private var collapsedProjects: Set<String> = []
    @State private var hoveredThreadID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader

            // Actions
            VStack(spacing: 0) {
                sidebarRow(icon: "plus", label: "New Session") {
                    sessionManager.openFolderPicker()
                }
                sidebarRow(icon: "square.and.arrow.down", label: "Import") {
                    sessionManager.showImportSheet = true
                }
            }
            .padding(.top, 4)

            // Sessions section
            if !sessionManager.sessions.isEmpty {
                sectionHeader("Sessions")
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    // Active sessions
                    if !sessionManager.sessions.isEmpty {
                        sessionList
                    }

                    // Thread history
                    if !projects.isEmpty {
                        threadHistory
                    }
                }
            }

            Spacer(minLength: 0)

            // Account & usage at bottom
            UsageView(auth: ClaudeAuthService.shared)
        }
        .background(Theme.bg)
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
            return true
        }
        .task { await loadHistory() }
    }

    // MARK: - Logo

    /// Safe resource bundle lookup that won't fatalError if the SPM resource bundle is missing.
    private static let resourceBundle: Bundle? = {
        let bundleName = "Claudex_Claudex"
        // Check alongside the executable (standard SPM layout)
        if let url = Bundle.main.url(forResource: bundleName, withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        // Check in Resources/ (app bundle layout)
        if let resourceURL = Bundle.main.resourceURL,
           let bundle = Bundle(url: resourceURL.appendingPathComponent("\(bundleName).bundle")) {
            return bundle
        }
        return nil
    }()

    static let logoImage: NSImage? = {
        guard let bundle = resourceBundle,
              let url = bundle.url(forResource: "claudex-logo", withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        return img
    }()

    static let iconImage: NSImage? = {
        guard let bundle = resourceBundle,
              let url = bundle.url(forResource: "claudex-icon", withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        return img
    }()

    private var brandHeader: some View {
        HStack(spacing: 8) {
            if let icon = Self.iconImage {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
            }
            if let logo = Self.logoImage {
                Image(nsImage: logo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 16)
            } else {
                Text("Claudex")
                    .font(Theme.brandFont)
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Action rows

    private func sidebarRow(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Theme.textDim)
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 8)
    }

    // MARK: - Session list

    private var sessionList: some View {
        ForEach(Array(sessionManager.sessions.enumerated()), id: \.element.id) { _, session in
            SessionRowView(
                session: session,
                isSelected: sessionManager.selectedSessionID == session.id,
                isHovered: hoveredID == session.id,
                editingSessionID: $editingSessionID
            )
            .onTapGesture { sessionManager.selectedSessionID = session.id }
            .onHover { h in hoveredID = h ? session.id : nil }
            .contextMenu {
                Button {
                    editingSessionID = session.id
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button {
                    sessionManager.revealInFinder(session)
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                Divider()
                Button(role: .destructive) {
                    sessionManager.closeSession(session)
                } label: {
                    Label("Close Session", systemImage: "xmark.circle")
                }
            }
        }
    }

    // MARK: - Thread history

    private var threadHistory: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Threads")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Theme.textDim)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 8)

            ForEach(projects) { project in
                projectSection(project)
            }
        }
    }

    private func projectSection(_ project: ClaudeProject) -> some View {
        let isCollapsed = collapsedProjects.contains(project.id)

        return VStack(alignment: .leading, spacing: 0) {
            // Project header — clickable to collapse/expand
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isCollapsed {
                        collapsedProjects.remove(project.id)
                    } else {
                        collapsedProjects.insert(project.id)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textDim)
                        .frame(width: 10)
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textDim)
                    Text(project.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(project.threads.count)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                // Threads — show 5 by default, more if expanded
                let isExpanded = expandedProjects.contains(project.id)
                let visibleCount = isExpanded ? project.threads.count : min(5, project.threads.count)
                let visibleThreads = Array(project.threads.prefix(visibleCount))

                ForEach(visibleThreads) { thread in
                    threadRow(thread)
                }

                // "Show more" button
                if project.threads.count > 5 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isExpanded {
                                expandedProjects.remove(project.id)
                            } else {
                                expandedProjects.insert(project.id)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .semibold))
                            Text(isExpanded ? "Show less" : "\(project.threads.count - 5) more")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(Theme.textDim)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func threadRow(_ thread: ClaudeThread) -> some View {
        let isActive = sessionManager.existingSession(forResumeID: thread.id) != nil

        return Button {
            openThread(thread)
        } label: {
            HStack(spacing: 6) {
                if isActive {
                    Circle()
                        .fill(Theme.green)
                        .frame(width: 5, height: 5)
                }
                Text(thread.displayName)
                    .font(.system(size: 12))
                    .foregroundStyle(
                        isActive ? Theme.textSecondary :
                        hoveredThreadID == thread.id ? Theme.textPrimary : Theme.textMuted
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if isActive {
                    Text("Active")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.green)
                } else {
                    Text(thread.timeLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textDim)
                }
            }
            .padding(.horizontal, 16)
            .padding(.leading, isActive ? 11 : 16)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in hoveredThreadID = h ? thread.id : nil }
        .background(hoveredThreadID == thread.id ? Theme.hover : Color.clear)
    }

    // MARK: - Thread actions

    private func openThread(_ thread: ClaudeThread) {
        let cmd = "claude --resume \(thread.id)"
        sessionManager.createSession(
            directory: thread.cwd,
            name: thread.displayName,
            initialCommand: cmd
        )
    }

    private func loadHistory() async {
        let result = await Task.detached {
            ClaudeHistoryScanner.scan()
        }.value
        projects = result
    }

    // MARK: - Empty state (unused now since threads fill space)

    // MARK: - Drop

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                      isDir.boolValue else { return }
                Task { @MainActor in
                    sessionManager.createSession(directory: url.path)
                }
            }
        }
    }
}
