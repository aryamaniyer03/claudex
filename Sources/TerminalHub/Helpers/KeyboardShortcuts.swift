import SwiftUI

struct AppCommands: Commands {
    @FocusedObject var sessionManager: SessionManager?

    var body: some Commands {
        // Replace default New Window with our New Terminal
        CommandGroup(replacing: .newItem) {
            Button("New Terminal") {
                sessionManager?.openFolderPicker()
            }
            .keyboardShortcut("t", modifiers: .command)
        }

        // Close session + import
        CommandGroup(after: .newItem) {
            Button("Import from Terminal.app\u{2026}") {
                sessionManager?.showImportSheet = true
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Divider()

            Button("Close Terminal") {
                sessionManager?.closeSelectedSession()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(sessionManager?.selectedSession == nil)
        }

        // View — font size + font picker + panel toggles
        CommandMenu("View") {
            Button("Toggle Sidebar") {
                sessionManager?.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])

            Button("Toggle Preview") {
                sessionManager?.togglePreviewPanel()
            }
            .keyboardShortcut("p", modifiers: [.command, .control])

            Button("Close All Previews") {
                sessionManager?.closeAllPreviews()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(sessionManager?.previewFiles.isEmpty ?? true)

            Divider()

            Button("Increase Font Size") {
                sessionManager?.increaseFontSize()
            }
            .keyboardShortcut("+", modifiers: .command)

            Button("Decrease Font Size") {
                sessionManager?.decreaseFontSize()
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Reset Font Size") {
                sessionManager?.resetFontSize()
            }
            .keyboardShortcut("0", modifiers: .command)

            Divider()

            // Font picker submenu
            Menu("Font") {
                ForEach(SessionManager.availableMonoFonts, id: \.self) { font in
                    Button {
                        sessionManager?.setFont(name: font)
                    } label: {
                        HStack {
                            Text(font)
                            if sessionManager?.fontName == font {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        }

        // Session navigation
        CommandMenu("Sessions") {
            Button("Next Session") {
                sessionManager?.selectNextSession()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])

            Button("Previous Session") {
                sessionManager?.selectPreviousSession()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])


            Divider()

            // ⌘1-9 for direct session access
            ForEach(1...9, id: \.self) { index in
                Button("Session \(index)") {
                    sessionManager?.selectSession(at: index - 1)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index))), modifiers: .command)
                .disabled(sessionManager == nil || index > (sessionManager?.sessions.count ?? 0))
            }
        }
    }
}
