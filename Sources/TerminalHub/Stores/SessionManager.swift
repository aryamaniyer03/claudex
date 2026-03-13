import AppKit
import SwiftUI

// MARK: - Persistence model

private struct SavedSession: Codable {
    let id: String
    let name: String
    let directory: String
    let hasCustomName: Bool
}

private struct SavedState: Codable {
    let sessions: [SavedSession]
    let selectedSessionID: String?
    let fontSize: CGFloat
    let fontName: String?
}

// MARK: - FocusedValueKey

struct SessionManagerKey: FocusedValueKey {
    typealias Value = SessionManager
}

extension FocusedValues {
    var sessionManager: SessionManager? {
        get { self[SessionManagerKey.self] }
        set { self[SessionManagerKey.self] = newValue }
    }
}

// MARK: - SessionManager

@MainActor
final class SessionManager: ObservableObject {
    @Published var sessions: [TerminalSession] = []
    @Published var selectedSessionID: UUID?
    @Published var showImportSheet = false
    @Published var fontSize: CGFloat = Theme.defaultFontSize
    @Published var fontName: String = "SF Mono"

    // Preview panel
    @Published var previewFiles: [PreviewFile] = []
    @Published var selectedPreviewID: UUID?
    private let previewWatcher = PreviewWatcher()
    /// User can hide the preview without closing files.
    @Published var previewHidden: Bool = false

    /// User can hide the sidebar (auto-hides when preview opens, toggleable).
    @Published var sidebarHidden: Bool = false

    /// Preview is visible when there are files and user hasn't hidden it.
    var isPreviewOpen: Bool { !previewFiles.isEmpty && !previewHidden }

    var selectedPreviewFile: PreviewFile? {
        guard let id = selectedPreviewID else { return nil }
        return previewFiles.first { $0.id == id }
    }

    private static let stateKey = "TerminalHub.savedState"

    var selectedSession: TerminalSession? {
        guard let id = selectedSessionID else { return nil }
        return sessions.first { $0.id == id }
    }

    init() {
        restoreState()
        previewWatcher.start { [weak self] url in
            self?.openPreview(url: url)
        }
        Self.installKeySwizzle(manager: self)
    }

    // MARK: - Cmd+Arrow key interception

    private static var keySwizzleInstalled = false

    private static weak var sharedManager: SessionManager?
    /// Exposed so PaddedContainerView can retry the swizzle after SwiftTerm loads.
    static var sharedForSwizzle: SessionManager? { sharedManager }

    /// Swizzle SwiftTerm's keyDown to intercept Cmd+Arrow for session nav.
    /// Called at init and again when first terminal is created, since
    /// SwiftTerm classes may not be loaded until first use.
    static func installKeySwizzle(manager: SessionManager) {
        sharedManager = manager
        guard !keySwizzleInstalled else { return }

        let classNames = ["SwiftTerm.LocalProcessTerminalView", "LocalProcessTerminalView"]
        guard let termClass = classNames.lazy.compactMap({ NSClassFromString($0) }).first else { return }
        let keySel = #selector(NSResponder.keyDown(with:))
        guard let keyMethod = class_getInstanceMethod(termClass, keySel) else { return }

        let origImpl = method_getImplementation(keyMethod)
        typealias KeyDownFn = @convention(c) (AnyObject, Selector, NSEvent) -> Void
        let origKeyDown = unsafeBitCast(origImpl, to: KeyDownFn.self)

        let block: @convention(block) (AnyObject, NSEvent) -> Void = { obj, event in
            let flags = event.modifierFlags
            if flags.contains(.command) && !flags.contains(.shift)
                && !flags.contains(.option) && !flags.contains(.control) {
                if event.keyCode == 125 { // Down arrow
                    DispatchQueue.main.async {
                        sharedManager?.selectNextSession()
                        // Force focus after SwiftUI swaps the terminal view
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            sharedManager?.selectedSession?.focus()
                        }
                    }
                    return
                } else if event.keyCode == 126 { // Up arrow
                    DispatchQueue.main.async {
                        sharedManager?.selectPreviousSession()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            sharedManager?.selectedSession?.focus()
                        }
                    }
                    return
                }
            }
            origKeyDown(obj, keySel, event)
        }
        method_setImplementation(keyMethod, imp_implementationWithBlock(block))
        keySwizzleInstalled = true
    }

    // MARK: - Preview

    func openPreview(url: URL) {
        // Don't open the same file twice — just select it
        if let existing = previewFiles.first(where: { $0.url == url }) {
            selectedPreviewID = existing.id
            previewHidden = false
            sidebarHidden = true
            return
        }
        let file = PreviewFile(url: url)
        previewFiles.append(file)
        selectedPreviewID = file.id
        previewHidden = false
        sidebarHidden = true
    }

    func closePreview(id: UUID) {
        previewFiles.removeAll { $0.id == id }
        if selectedPreviewID == id {
            selectedPreviewID = previewFiles.last?.id
        }
        if previewFiles.isEmpty {
            previewHidden = false
            sidebarHidden = false
        }
    }

    func closeAllPreviews() {
        previewFiles.removeAll()
        selectedPreviewID = nil
        previewHidden = false
        sidebarHidden = false
    }

    func togglePreviewPanel() {
        if previewFiles.isEmpty { return }
        previewHidden.toggle()
        // When hiding preview and sidebar was auto-hidden, bring sidebar back
        if previewHidden && !isPreviewOpen {
            sidebarHidden = false
        }
    }

    func toggleSidebar() {
        sidebarHidden.toggle()
    }

    // MARK: - Session CRUD

    /// Returns an existing session matching the directory, or nil.
    func existingSession(forDirectory directory: String) -> TerminalSession? {
        sessions.first { $0.currentDirectory == directory || $0.currentDirectory == (directory as NSString).standardizingPath }
    }

    /// Returns an existing session that was resumed with this session ID, or nil.
    func existingSession(forResumeID resumeID: String) -> TerminalSession? {
        sessions.first { $0.resumeSessionID == resumeID }
    }

    func createSession(directory: String, name: String? = nil, initialCommand: String? = nil) {
        // Check for duplicate by resume session ID
        if let cmd = initialCommand, cmd.contains("--resume") {
            let parts = cmd.split(separator: " ")
            if let idx = parts.firstIndex(of: "--resume"), idx + 1 < parts.count {
                let resumeID = String(parts[idx + 1])
                if let existing = existingSession(forResumeID: resumeID) {
                    selectedSessionID = existing.id
                    return
                }
            }
        }

        let folderName = name ?? (directory as NSString).lastPathComponent
        let session = TerminalSession(name: folderName, directory: directory, fontSize: fontSize, fontName: fontName, initialCommand: initialCommand)
        sessions.append(session)
        selectedSessionID = session.id
        saveState()
    }

    func closeSession(_ session: TerminalSession) {
        session.terminate()
        sessions.removeAll { $0.id == session.id }
        if selectedSessionID == session.id {
            selectedSessionID = sessions.last?.id
        }
        saveState()
    }

    func closeSelectedSession() {
        guard let session = selectedSession else { return }
        closeSession(session)
    }

    func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to open in a new terminal"
        panel.prompt = "Open Terminal Here"

        if panel.runModal() == .OK, let url = panel.url {
            createSession(directory: url.path)
        }
    }

    // MARK: - Navigation

    func selectSession(at index: Int) {
        guard index >= 0 && index < sessions.count else { return }
        selectedSessionID = sessions[index].id
        saveState()
    }

    func selectNextSession() {
        guard !sessions.isEmpty else { return }
        guard let currentID = selectedSessionID,
              let currentIndex = sessions.firstIndex(where: { $0.id == currentID }) else {
            selectedSessionID = sessions.first?.id
            saveState()
            return
        }
        let nextIndex = (currentIndex + 1) % sessions.count
        selectedSessionID = sessions[nextIndex].id
        saveState()
    }

    func selectPreviousSession() {
        guard !sessions.isEmpty else { return }
        guard let currentID = selectedSessionID,
              let currentIndex = sessions.firstIndex(where: { $0.id == currentID }) else {
            selectedSessionID = sessions.last?.id
            saveState()
            return
        }
        let prevIndex = (currentIndex - 1 + sessions.count) % sessions.count
        selectedSessionID = sessions[prevIndex].id
        saveState()
    }

    func revealInFinder(_ session: TerminalSession) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: session.currentDirectory)
    }

    // MARK: - Font size

    func increaseFontSize() {
        setFontSize(min(fontSize + 1, Theme.maxFontSize))
    }

    func decreaseFontSize() {
        setFontSize(max(fontSize - 1, Theme.minFontSize))
    }

    func resetFontSize() {
        setFontSize(Theme.defaultFontSize)
    }

    func setFont(name: String) {
        fontName = name
        applyFont()
        saveState()
    }

    private func setFontSize(_ size: CGFloat) {
        fontSize = size
        applyFont()
        saveState()
    }

    private func applyFont() {
        let font = NSFont(name: fontName, size: fontSize)
            ?? NSFont(name: "Menlo", size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        for session in sessions {
            session.updateFont(font)
        }
    }

    /// Monospace fonts available on the system, suitable for terminal use.
    static var availableMonoFonts: [String] {
        let preferred = [
            "SF Mono", "Menlo", "Monaco",
            "JetBrains Mono", "JetBrainsMono-Regular",
            "Fira Code", "FiraCode-Regular",
            "Source Code Pro", "Cascadia Code", "Cascadia Mono",
            "IBM Plex Mono", "Hack", "Inconsolata",
            "Ubuntu Mono", "Roboto Mono", "Anonymous Pro",
            "Courier New", "Courier",
        ]
        let available = Set(NSFontManager.shared.availableFontFamilies)
        // Also check postscript names for fonts that have different family names
        let allFonts = Set(NSFontManager.shared.availableFonts)
        return preferred.filter { name in
            available.contains(name) || allFonts.contains(name) ||
            NSFont(name: name, size: 13) != nil
        }
    }

    // MARK: - Persistence

    private func saveState() {
        let saved = SavedState(
            sessions: sessions.map { SavedSession(id: $0.id.uuidString, name: $0.name, directory: $0.currentDirectory, hasCustomName: $0.hasCustomName) },
            selectedSessionID: selectedSessionID?.uuidString,
            fontSize: fontSize,
            fontName: fontName
        )
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: Self.stateKey)
        }
    }

    private func restoreState() {
        guard let data = UserDefaults.standard.data(forKey: Self.stateKey),
              let saved = try? JSONDecoder().decode(SavedState.self, from: data) else {
            return
        }

        fontSize = saved.fontSize
        if let name = saved.fontName, !name.isEmpty {
            fontName = name
        }

        for s in saved.sessions {
            guard let uuid = UUID(uuidString: s.id) else { continue }
            // Only restore if the directory still exists
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: s.directory, isDirectory: &isDir),
                  isDir.boolValue else { continue }
            let session = TerminalSession(name: s.name, directory: s.directory, fontSize: fontSize, fontName: fontName, id: uuid)
            session.hasCustomName = s.hasCustomName
            sessions.append(session)
        }

        if let selID = saved.selectedSessionID, let uuid = UUID(uuidString: selID),
           sessions.contains(where: { $0.id == uuid }) {
            selectedSessionID = uuid
        } else {
            selectedSessionID = sessions.first?.id
        }
    }
}
