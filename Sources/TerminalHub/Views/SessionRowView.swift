import SwiftUI

struct SessionRowView: View {
    @ObservedObject var session: TerminalSession
    let isSelected: Bool
    let isHovered: Bool
    @Binding var editingSessionID: UUID?

    @State private var editText: String = ""
    @FocusState private var isEditing: Bool

    private var isEditingThis: Bool { editingSessionID == session.id }

    var body: some View {
        HStack(spacing: 0) {
            if isEditingThis {
                TextField("Session name", text: $editText)
                    .font(.system(size: 14))
                    .textFieldStyle(.plain)
                    .focused($isEditing)
                    .onSubmit { commitEdit() }
                    .onChange(of: isEditing) { _, focused in
                        if !focused { commitEdit() }
                    }
                    .onAppear {
                        editText = displayName
                        isEditing = true
                    }
            } else {
                Text(displayName)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onDoubleClick { startEditing() }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(isSelected ? Theme.selected : (isHovered ? Theme.hover : Color.clear))
            .padding(.horizontal, 6)
    }

    // MARK: - Editing

    func startEditing() {
        editText = displayName
        editingSessionID = session.id
    }

    private func commitEdit() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            session.name = trimmed
            session.hasCustomName = true
        }
        editingSessionID = nil
    }

    // MARK: - Helpers

    var displayName: String {
        let name = session.name
        let boring: Set<String> = ["zsh", "bash", "fish", "sh", "-zsh", "-bash", "-fish"]
        if boring.contains(name.lowercased()) {
            return (session.currentDirectory as NSString).lastPathComponent
        }
        return name
    }
}

// MARK: - Double-click modifier

private struct DoubleClickModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content.overlay {
            DoubleClickView(action: action)
        }
    }
}

private struct DoubleClickView: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = DoubleClickNSView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? DoubleClickNSView)?.action = action
    }
}

private class DoubleClickNSView: NSView {
    var action: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            action?()
        } else {
            super.mouseDown(with: event)
        }
    }
}

extension View {
    func onDoubleClick(perform action: @escaping () -> Void) -> some View {
        modifier(DoubleClickModifier(action: action))
    }
}
