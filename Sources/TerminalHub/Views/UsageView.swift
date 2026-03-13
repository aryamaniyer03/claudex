import SwiftUI

/// Usage panel at the bottom of the sidebar — glanceable inline usage bars
/// with expandable detail on click.
struct UsageView: View {
    @ObservedObject var auth: ClaudeAuthService

    @State private var expanded = false
    @State private var hovered = false

    var body: some View {
        if auth.isLoggedIn {
            loggedInView
        } else {
            loggedOutView
        }
    }

    // MARK: - Logged out

    private var loggedOutView: some View {
        VStack(spacing: 0) {
            Theme.border.frame(height: 1)
            Button {
                auth.recheckCredentials()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connect to Claude Code")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        Text("Run 'claude login' in terminal")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Logged in

    private var loggedInView: some View {
        VStack(spacing: 0) {
            Theme.border.frame(height: 1)

            // Always-visible compact section
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.toggle()
                }
            } label: {
                VStack(spacing: 8) {
                    // Top row: avatar + name + plan badge
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Theme.accent.opacity(0.15))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Text(initials)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                            )

                        Text(auth.accountName ?? auth.organizationName ?? "Claude")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)

                        Spacer()

                        // Plan badge
                        Text(auth.planType ?? "Pro")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Theme.accent.opacity(0.12))
                            )

                        Image(systemName: expanded ? "chevron.down" : "chevron.up")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.textDim)
                    }

                    // Inline usage bars — always visible
                    HStack(spacing: 10) {
                        miniBar(
                            label: "Session",
                            pct: auth.usage.sessionPercentage
                        )
                        miniBar(
                            label: "Weekly",
                            pct: auth.usage.weeklyPercentage
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .background(hovered ? Theme.hover : Color.clear)

            // Expanded detail section
            if expanded {
                expandedSection
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Mini usage bar (always visible)

    private func miniBar(label: String, pct: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textDim)
                Spacer()
                Text("\(Int(min(pct, 100)))%")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(usageColor(pct))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.surface)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(usageColor(pct))
                        .frame(width: max(0, geo.size.width * CGFloat(min(pct, 100) / 100)))
                }
            }
            .frame(height: 3)
        }
    }

    // MARK: - Expanded section

    private var expandedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Theme.border.frame(height: 1)
                .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 12) {
                // Session detail
                usageDetail(
                    icon: "clock",
                    title: "Session",
                    pct: auth.usage.sessionPercentage,
                    resetLabel: auth.usage.sessionResetLabel()
                )

                // Weekly detail
                usageDetail(
                    icon: "calendar",
                    title: "Weekly",
                    pct: auth.usage.weeklyPercentage,
                    resetLabel: auth.usage.weeklyResetLabel()
                )

                // Last updated + refresh
                HStack(spacing: 4) {
                    Text("Updated \(timeAgo(auth.usage.lastUpdated))")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textDim)

                    Spacer()

                    Button {
                        Task { await auth.refreshUsage() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textMuted)
                            .rotationEffect(.degrees(auth.isLoading ? 360 : 0))
                            .animation(
                                auth.isLoading
                                    ? .linear(duration: 1).repeatForever(autoreverses: false)
                                    : .default,
                                value: auth.isLoading
                            )
                    }
                    .buttonStyle(.plain)
                }

                Theme.border.frame(height: 1)

                // Actions row
                HStack(spacing: 16) {
                    Button {
                        auth.logout()
                        expanded = false
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10))
                            Text("Disconnect")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(Theme.textMuted)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Text("Quit")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Usage detail row

    private func usageDetail(icon: String, title: String, pct: Double, resetLabel: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(usageColor(pct))
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(Int(min(pct, 100)))%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(usageColor(pct))
                }

                // Full-width bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(Theme.surface)

                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(usageColor(pct))
                            .frame(width: max(0, geo.size.width * CGFloat(min(pct, 100) / 100)))
                    }
                }
                .frame(height: 4)

                Text(resetLabel)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textDim)
            }
        }
    }

    // MARK: - Helpers

    private func usageColor(_ pct: Double) -> Color {
        if pct >= 80 { return Theme.red }
        if pct >= 50 { return Theme.accent }
        return Theme.green
    }

    private var initials: String {
        let name = auth.accountName ?? auth.organizationName ?? "C"
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(name.prefix(1)).uppercased()
    }

    private func timeAgo(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        fmt.timeZone = .current
        let timeStr = fmt.string(from: date)

        if diff < 60 { return "just now (\(timeStr))" }
        if diff < 3600 { return "\(Int(diff / 60)) min ago (\(timeStr))" }
        return "\(Int(diff / 3600)) hr ago (\(timeStr))"
    }
}
