import AppKit
import QuickLookUI
import SwiftUI

/// Tab bar + Quick Look preview for files opened in the right panel.
struct PreviewPanelView: View {
    @ObservedObject var sessionManager: SessionManager

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Theme.border.frame(height: 1)
            previewContent
        }
        .background(Theme.bg)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(sessionManager.previewFiles) { file in
                    previewTab(file: file)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 34)
        .background(Theme.surface)
    }

    private func previewTab(file: PreviewFile) -> some View {
        let isSelected = sessionManager.selectedPreviewID == file.id
        return HStack(spacing: 5) {
            Image(systemName: file.iconName)
                .font(.system(size: 10))
                .foregroundStyle(isSelected ? Theme.accent : Theme.textDim)

            Text(file.name)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)

            Button {
                sessionManager.closePreview(id: file.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.textDim)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isSelected ? Theme.selected : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            sessionManager.selectedPreviewID = file.id
        }
    }

    // MARK: - Preview content

    @ViewBuilder
    private var previewContent: some View {
        if let file = sessionManager.selectedPreviewFile {
            QuickLookView(url: file.url)
                .id(file.id)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "eye")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Theme.textFaint)
                Text("No file selected")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textDim)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Quick Look NSViewRepresentable

struct QuickLookView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        view.previewItem = url as NSURL
    }
}
