import SwiftUI

@main
struct ClaudexApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var sessionManager = SessionManager()
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "Claudex.onboardingComplete")

    var body: some Scene {
        WindowGroup {
            ContentView(sessionManager: sessionManager)
                .frame(minWidth: 600, minHeight: 400)
                .preferredColorScheme(.dark)
                .sheet(isPresented: $showOnboarding) {
                    OnboardingView(sessionManager: sessionManager, isPresented: $showOnboarding)
                        .preferredColorScheme(.dark)
                }
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            AppCommands()
        }
    }
}
