import Foundation

/// Calls an LLM API to generate short session titles from terminal output.
/// Requires OPENROUTER_API_KEY environment variable or falls back to a simple heuristic.
enum LLMService {
    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private static let model = "anthropic/claude-3-haiku"

    /// Generate a short (3-6 word) title summarizing what the user is doing in this terminal session.
    static func generateTitle(from terminalOutput: String) async -> String? {
        // Try API-based title generation if key is available
        if let apiKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !apiKey.isEmpty {
            return await generateTitleViaAPI(from: terminalOutput, apiKey: apiKey)
        }
        // Fallback: extract title from terminal content heuristically
        return heuristicTitle(from: terminalOutput)
    }

    private static func generateTitleViaAPI(from terminalOutput: String, apiKey: String) async -> String? {
        let snippet = terminalOutput.count > 1500
            ? String(terminalOutput.suffix(1500))
            : terminalOutput

        let systemPrompt = """
        You generate very short titles (3-6 words) for terminal sessions based on what the user is doing. \
        The title should describe the activity, like a chat title. Examples: \
        "React app development", "Django API debugging", "Git repo cleanup", \
        "Docker container setup", "Python data analysis", "iOS build fixes". \
        Respond with ONLY the title, nothing else. No quotes, no punctuation at the end.
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 20,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "Here is recent terminal output. Generate a short title:\n\n\(snippet)"]
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else { return nil }
            let title = content.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        } catch {
            return nil
        }
    }

    /// Simple heuristic: extract the directory name and any recognizable command.
    private static func heuristicTitle(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        // Look for common tool names in the output
        let tools = ["claude", "git", "npm", "pnpm", "yarn", "cargo", "swift", "python",
                     "docker", "kubectl", "terraform", "make", "cmake", "go", "ruby", "pip"]
        for line in lines.prefix(20) {
            let lower = line.lowercased()
            for tool in tools {
                if lower.contains(tool) {
                    return nil // Let the directory name suffice — heuristic isn't confident enough
                }
            }
        }
        return nil
    }
}
