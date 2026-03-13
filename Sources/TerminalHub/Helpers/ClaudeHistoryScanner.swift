import Foundation

/// Scans ~/.claude/projects/ for Claude Code conversation history.
enum ClaudeHistoryScanner {

    /// Scan all projects and return them grouped and sorted.
    static func scan() -> [ClaudeProject] {
        let projectsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")

        guard let projectDirs = try? FileManager.default.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: nil
        ) else { return [] }

        var projects: [ClaudeProject] = []

        for projURL in projectDirs {
            guard projURL.hasDirectoryPath else { continue }
            let projName = projURL.lastPathComponent

            // Skip memory directories
            if projName == "memory" { continue }

            // Find JSONL files (skip subagent dirs)
            let jsonlFiles: [URL]
            do {
                jsonlFiles = try FileManager.default.contentsOfDirectory(
                    at: projURL, includingPropertiesForKeys: [.contentModificationDateKey]
                ).filter { $0.pathExtension == "jsonl" }
            } catch {
                continue
            }

            if jsonlFiles.isEmpty { continue }

            var threads: [ClaudeThread] = []

            for file in jsonlFiles {
                let sessionId = file.deletingPathExtension().lastPathComponent

                // Get modification date
                let mtime: Date
                if let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                   let date = attrs.contentModificationDate {
                    mtime = date
                } else {
                    mtime = Date.distantPast
                }

                // Parse first few lines for metadata
                let meta = parseConversationMeta(file)

                threads.append(ClaudeThread(
                    id: sessionId,
                    projectDir: projName,
                    cwd: meta.cwd ?? decodeProjPath(projName),
                    slug: meta.slug,
                    firstMessage: meta.firstMessage,
                    modifiedAt: mtime
                ))
            }

            // Sort threads newest first
            threads.sort { $0.modifiedAt > $1.modifiedAt }

            let realPath = threads.first?.cwd ?? decodeProjPath(projName)
            let displayName = (realPath as NSString).lastPathComponent

            projects.append(ClaudeProject(
                id: projName,
                name: displayName,
                path: realPath,
                threads: threads
            ))
        }

        // Sort projects by most recent thread
        projects.sort { ($0.threads.first?.modifiedAt ?? .distantPast) > ($1.threads.first?.modifiedAt ?? .distantPast) }

        return projects
    }

    // MARK: - Private

    private struct ConversationMeta {
        var cwd: String?
        var slug: String?
        var firstMessage: String?
    }

    private static func parseConversationMeta(_ file: URL) -> ConversationMeta {
        var meta = ConversationMeta()

        guard let handle = try? FileHandle(forReadingFrom: file) else { return meta }
        defer { handle.closeFile() }

        // Read first 8KB — enough for metadata
        let data = handle.readData(ofLength: 8192)
        guard let text = String(data: data, encoding: .utf8) else { return meta }

        for line in text.split(separator: "\n").prefix(20) {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            let type = json["type"] as? String ?? ""

            if type == "user" {
                if meta.cwd == nil { meta.cwd = json["cwd"] as? String }
                if meta.slug == nil { meta.slug = json["slug"] as? String }

                if meta.firstMessage == nil {
                    // Try message.content (newer format) then direct content
                    if let msg = json["message"] as? [String: Any] {
                        if let content = msg["content"] as? String {
                            meta.firstMessage = String(content.prefix(100))
                        } else if let parts = msg["content"] as? [[String: Any]],
                                  let first = parts.first,
                                  let text = first["text"] as? String {
                            meta.firstMessage = String(text.prefix(100))
                        }
                    }
                }

                // Got what we need
                if meta.cwd != nil && meta.slug != nil { break }
            } else if type == "summary" {
                meta.firstMessage = json["summary"] as? String
            }
        }

        return meta
    }

    /// Decode a project directory name back to a filesystem path.
    /// e.g. "-Volumes-Coder-EQ--Analyst" → "/Volumes/Coder/EQ+ Analyst"
    private static func decodeProjPath(_ encoded: String) -> String {
        // The encoding replaces / with - and some special chars
        // But we can't perfectly reverse it, so just replace leading dashes with /
        var path = encoded
        // Handle double-dash (represents special chars like + in the original)
        // This is a best-effort decode
        if path.hasPrefix("-") {
            path = "/" + String(path.dropFirst())
        }
        path = path.replacingOccurrences(of: "-", with: "/")
        // Double-slash was double-dash (special char boundary) — not perfect but close enough
        return path
    }
}
