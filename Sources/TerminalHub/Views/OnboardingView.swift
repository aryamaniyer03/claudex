import SwiftUI

/// First-run onboarding flow shown before any sessions exist.
struct OnboardingView: View {
    @ObservedObject var sessionManager: SessionManager
    @Binding var isPresented: Bool
    @State private var currentPage = 0

    private let pages: [(icon: String, title: String, subtitle: String, detail: String)] = [
        (
            "terminal",
            "Welcome to Claudex",
            "A native macOS home for your Claude Code sessions.",
            "Manage all your terminal sessions in one window with persistent tmux sessions that survive app restarts."
        ),
        (
            "rectangle.stack",
            "Multi-session workspace",
            "Switch between sessions instantly.",
            "Use Cmd+Up/Down to navigate sessions, Cmd+1-9 for direct access, or click the sidebar. Each session runs in its own tmux pane."
        ),
        (
            "clock.arrow.circlepath",
            "Thread history",
            "Resume any past Claude Code conversation.",
            "Your conversation history is indexed by project. Click any thread in the sidebar to pick up where you left off."
        ),
        (
            "square.and.arrow.down",
            "Import & drag-and-drop",
            "Bring in sessions from Terminal.app.",
            "Use Import (Cmd+Shift+I) to absorb running Claude Code sessions, or drag any folder from Finder into the sidebar."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: pages[currentPage].icon)
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.bottom, 24)

            // Title
            Text(pages[currentPage].title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.bottom, 6)

            // Subtitle
            Text(pages[currentPage].subtitle)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 12)

            // Detail
            Text(pages[currentPage].detail)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .lineSpacing(4)

            Spacer()

            // Page dots
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { i in
                    Circle()
                        .fill(i == currentPage ? Theme.accent : Theme.textFaint)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.bottom, 24)

            // Buttons
            HStack(spacing: 12) {
                if currentPage > 0 {
                    Button("Back") {
                        withAnimation { currentPage -= 1 }
                    }
                    .buttonStyle(OnboardingButtonStyle(isProminent: false))
                }

                Spacer()

                if currentPage < pages.count - 1 {
                    Button("Next") {
                        withAnimation { currentPage += 1 }
                    }
                    .buttonStyle(OnboardingButtonStyle(isProminent: true))
                } else {
                    Button("Get Started") {
                        completeOnboarding()
                    }
                    .buttonStyle(OnboardingButtonStyle(isProminent: true))
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
        .frame(width: 480, height: 420)
        .background(Theme.bg)
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "Claudex.onboardingComplete")
        isPresented = false
    }
}

private struct OnboardingButtonStyle: ButtonStyle {
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: isProminent ? .semibold : .medium))
            .foregroundStyle(isProminent ? .white : Theme.textMuted)
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isProminent
                          ? (configuration.isPressed ? Theme.accentDim : Theme.accent)
                          : (configuration.isPressed ? Theme.selected : Theme.surface))
            )
    }
}
