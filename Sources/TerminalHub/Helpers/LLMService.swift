import Foundation

/// Generates short session titles using the user's Claude Code OAuth token.
/// Uses a configurable Anthropic model via the Messages API.
enum LLMService {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let defaultModel = "claude-3-5-haiku-latest"

    /// Allow overrides so releases are not tied to one historical model snapshot.
    private static var model: String {
        let env = ProcessInfo.processInfo.environment["CLAUDEX_AUTOTITLE_MODEL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let env, !env.isEmpty {
            return env
        }

        let stored = UserDefaults.standard.string(forKey: "Claudex.autoTitleModel")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty {
            return stored
        }

        return defaultModel
    }

    /// Generate a short (3-6 word) title from terminal output.
    @MainActor
    static func generateTitle(from terminalOutput: String) async -> String? {
        guard let token = await ClaudeAuthService.shared.ensureValidToken() else { return nil }

        let snippet = terminalOutput.count > 1500
            ? String(terminalOutput.suffix(1500))
            : terminalOutput

        let systemPrompt = "You generate very short titles (3-6 words) for terminal sessions. " +
            "Describe the activity like a chat title. Examples: " +
            "React app development, Django API debugging, Git repo cleanup. " +
            "Respond with ONLY the title. No quotes, no punctuation at the end."

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 20,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": "Here is recent terminal output. Generate a short title:\n\n\(snippet)"]
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = jsonData
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? [[String: Any]],
                  let text = content.first?["text"] as? String else { return nil }
            let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        } catch {
            return nil
        }
    }
}
