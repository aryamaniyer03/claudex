import Foundation

/// Manages Claude authentication by reading Claude Code's OAuth credentials
/// from the macOS Keychain. No webview login needed — piggybacks on existing
/// `claude login` authentication.
@MainActor
final class ClaudeAuthService: ObservableObject {
    static let shared = ClaudeAuthService()

    @Published var isLoggedIn = false
    @Published var usage: ClaudeUsage = .empty
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var organizationName: String?
    @Published var planType: String?
    @Published var accountName: String?

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiresAt: Date?
    private var refreshTimer: Timer?
    /// Cached last successful usage — shown when API is rate-limited or unavailable.
    private var cachedUsage: ClaudeUsage?

    private let oauthClientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private let keychainService = "Claude Code-credentials"

    private init() {
        loadCredentials()
        if isLoggedIn {
            startAutoRefresh()
            Task {
                await fetchProfile()
                await refreshUsage()
            }
        }
    }

    // MARK: - Credential Loading

    /// Try to load Claude Code OAuth credentials from macOS Keychain.
    func loadCredentials() {
        if let creds = readFromKeychain() {
            accessToken = creds.accessToken
            refreshToken = creds.refreshToken
            tokenExpiresAt = creds.expiresAt
            if let sub = creds.subscriptionType {
                planType = sub.capitalized
            }
            isLoggedIn = true
            errorMessage = nil
        } else {
            isLoggedIn = false
        }
    }

    /// Re-check for credentials (e.g. after user runs `claude login`).
    func recheckCredentials() {
        let wasLoggedIn = isLoggedIn
        loadCredentials()
        if isLoggedIn && !wasLoggedIn {
            startAutoRefresh()
            Task {
                await fetchProfile()
                await refreshUsage()
            }
        }
    }

    func logout() {
        accessToken = nil
        refreshToken = nil
        tokenExpiresAt = nil
        isLoggedIn = false
        usage = .empty
        organizationName = nil
        planType = nil
        accountName = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Keychain

    private struct OAuthCreds {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date?
        let subscriptionType: String?
    }

    private func readFromKeychain() -> OAuthCreds? {
        // Use `security` CLI — no Keychain prompt dialogs, inherits user access
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = ["find-generic-password", "-s", keychainService, "-w"]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            return parseCredentialJSON(data)
        } catch {
            return nil
        }
    }

    private func parseCredentialJSON(_ data: Data) -> OAuthCreds? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        // Navigate to claudeAiOauth key, or use top-level
        let oauth: [String: Any]
        if let nested = json["claudeAiOauth"] as? [String: Any] {
            oauth = nested
        } else if json["accessToken"] != nil {
            oauth = json
        } else {
            return nil
        }

        guard let at = oauth["accessToken"] as? String,
              let rt = oauth["refreshToken"] as? String else { return nil }

        // expiresAt is epoch milliseconds
        var expiresAt: Date?
        if let ms = oauth["expiresAt"] as? Double {
            expiresAt = Date(timeIntervalSince1970: ms / 1000)
        } else if let ms = oauth["expiresAt"] as? Int {
            expiresAt = Date(timeIntervalSince1970: Double(ms) / 1000)
        }

        let subType = oauth["subscriptionType"] as? String
        return OAuthCreds(accessToken: at, refreshToken: rt, expiresAt: expiresAt, subscriptionType: subType)
    }

    // MARK: - Token Refresh

    private func ensureValidToken() async -> String? {
        guard var token = accessToken else { return nil }

        // If token expires within 5 minutes, refresh it
        if let exp = tokenExpiresAt, exp.timeIntervalSinceNow < 300 {
            if let newToken = await doTokenRefresh() {
                token = newToken
            } else {
                // Refresh failed — try re-reading from Keychain (Claude Code may have refreshed it)
                loadCredentials()
                token = accessToken ?? token
            }
        }

        return token
    }

    private func doTokenRefresh() async -> String? {
        guard let rt = refreshToken else { return nil }

        let url = URL(string: "https://console.anthropic.com/v1/oauth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body = "grant_type=refresh_token&refresh_token=\(rt)&client_id=\(oauthClientId)"
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAT = json["access_token"] as? String else { return nil }

            accessToken = newAT
            if let newRT = json["refresh_token"] as? String {
                refreshToken = newRT
            }
            if let expiresIn = json["expires_in"] as? Double {
                tokenExpiresAt = Date().addingTimeInterval(expiresIn)
            }
            return newAT
        } catch {
            return nil
        }
    }

    // MARK: - Auto Refresh

    func startAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshUsage()
            }
        }
    }

    // MARK: - Profile

    private func fetchProfile() async {
        guard let token = await ensureValidToken() else { return }

        let url = URL(string: "https://api.anthropic.com/api/oauth/profile")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            if let account = json["account"] as? [String: Any] {
                accountName = account["display_name"] as? String ?? account["full_name"] as? String
            }

            if let org = json["organization"] as? [String: Any] {
                let orgType = org["organization_type"] as? String ?? ""
                if orgType.contains("max") {
                    planType = "Max"
                } else if orgType.contains("pro") {
                    planType = "Pro"
                }
                // Use display name or derive from org name
                if let name = org["name"] as? String {
                    organizationName = name
                }
            }
        } catch {
            // Non-critical — profile fetch failure doesn't affect usage
        }
    }

    // MARK: - Usage

    func refreshUsage() async {
        guard let token = await ensureValidToken() else {
            recheckCredentials()
            return
        }

        isLoading = true
        errorMessage = nil

        let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            if http.statusCode == 429 {
                // Rate limited — serve cached data, don't treat as error
                if let cached = cachedUsage {
                    usage = cached
                }
                isLoading = false
                return
            } else if http.statusCode == 401 || http.statusCode == 403 {
                if let newToken = await doTokenRefresh() {
                    var retryReq = request
                    retryReq.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                    let (retryData, retryResp) = try await URLSession.shared.data(for: retryReq)
                    guard let retryHttp = retryResp as? HTTPURLResponse, retryHttp.statusCode == 200 else {
                        throw APIError.unauthorized
                    }
                    let fresh = try parseUsageResponse(retryData)
                    cachedUsage = fresh
                    usage = fresh
                } else {
                    loadCredentials()
                    throw APIError.unauthorized
                }
            } else if http.statusCode == 200 {
                let fresh = try parseUsageResponse(data)
                cachedUsage = fresh
                usage = fresh
            } else {
                throw APIError.serverError(http.statusCode)
            }
        } catch {
            // On any error, serve cached data if available
            if let cached = cachedUsage {
                usage = cached
            } else {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
    }

    private func parseUsageResponse(_ data: Data) throws -> ClaudeUsage {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.parseFailed
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // five_hour = current session
        var sessionPct = 0.0
        var sessionReset = Date().addingTimeInterval(5 * 3600)
        if let fiveHour = json["five_hour"] as? [String: Any] {
            sessionPct = (fiveHour["utilization"] as? Double) ?? 0
            if let r = fiveHour["resets_at"] as? String {
                sessionReset = isoFormatter.date(from: r) ?? sessionReset
            }
        }

        // seven_day = weekly
        var weeklyPct = 0.0
        var weeklyReset = Date().addingTimeInterval(7 * 24 * 3600)
        if let sevenDay = json["seven_day"] as? [String: Any] {
            weeklyPct = (sevenDay["utilization"] as? Double) ?? 0
            if let r = sevenDay["resets_at"] as? String {
                weeklyReset = isoFormatter.date(from: r) ?? weeklyReset
            }
        }

        return ClaudeUsage(
            sessionPercentage: sessionPct,
            sessionResetTime: sessionReset,
            weeklyPercentage: weeklyPct,
            weeklyResetTime: weeklyReset,
            lastUpdated: Date()
        )
    }

    // MARK: - Errors

    enum APIError: Error, Equatable {
        case unauthorized
        case invalidResponse
        case serverError(Int)
        case parseFailed
    }
}
