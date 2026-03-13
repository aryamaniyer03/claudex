import SwiftUI

struct ContentView: View {
    @ObservedObject var sessionManager: SessionManager

    var body: some View {
        GeometryReader { geo in
            let showSidebar = !sessionManager.sidebarHidden
            let showPreview = sessionManager.isPreviewOpen
            let sidebarW: CGFloat = 240
            let availableW = geo.size.width - (showSidebar ? sidebarW : 0)

            HStack(spacing: 0) {
                if showSidebar {
                    SidebarView(sessionManager: sessionManager)
                        .frame(width: sidebarW)
                    Theme.border.frame(width: 1)
                }

                // Terminal
                Group {
                    if let session = sessionManager.selectedSession {
                        TerminalContainerView(session: session, sessionManager: sessionManager)
                            .id(session.id)
                    } else {
                        EmptyStateView(sessionManager: sessionManager)
                    }
                }
                .frame(width: showPreview ? availableW * 0.5 : availableW)
                .frame(maxHeight: .infinity)

                if showPreview {
                    Theme.border.frame(width: 1)
                    PreviewPanelView(sessionManager: sessionManager)
                        .frame(width: availableW * 0.5)
                        .frame(maxHeight: .infinity)
                }
            }
        }
        .focusedObject(sessionManager)
        .sheet(isPresented: $sessionManager.showImportSheet) {
            ImportTerminalsView(sessionManager: sessionManager,
                                isPresented: $sessionManager.showImportSheet)
        }
        .background(Theme.bg)
    }
}
