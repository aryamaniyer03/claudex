import SwiftUI

struct EmptyStateView: View {
    @ObservedObject var sessionManager: SessionManager

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                iconBox
                titleSection
                actionButtons
            }

            Spacer()

            Text("You can also drag folders from Finder into the sidebar")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textFaint)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }

    private var iconBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.surface)
                .frame(width: 80, height: 80)
            Image(systemName: "terminal")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.6))
        }
    }

    private var titleSection: some View {
        VStack(spacing: 8) {
            if let logo = SidebarView.logoImage {
                Image(nsImage: logo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 30)
            } else {
                Text("Claudex")
                    .font(.custom("Georgia", size: 22).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("Start a new Claude session or import from Terminal.app")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            emptyButton(icon: "plus", label: "New Session", shortcut: "\u{2318}T") {
                sessionManager.openFolderPicker()
            }
            emptyButton(icon: "square.and.arrow.down", label: "Import", shortcut: "\u{2318}\u{21E7}I") {
                sessionManager.showImportSheet = true
            }
        }
    }

    private func emptyButton(icon: String, label: String, shortcut: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12, weight: .medium))
                Text(label).font(.system(size: 12, weight: .medium))
                Text(shortcut)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textDim)
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
