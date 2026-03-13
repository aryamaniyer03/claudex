import Foundation

/// Watches ~/.claudex/preview-request for file paths written by `claudex-open`.
/// When the file changes, reads the path, opens it, and clears the file.
@MainActor
final class PreviewWatcher {
    private let requestDir: String
    private let requestFile: String
    private var fileSource: DispatchSourceFileSystemObject?
    private var handler: ((URL) -> Void)?
    private var pollTimer: Timer?

    init() {
        requestDir = NSHomeDirectory() + "/.claudex"
        requestFile = requestDir + "/preview-request"
    }

    func start(handler: @escaping (URL) -> Void) {
        self.handler = handler

        // Ensure directory and file exist
        try? FileManager.default.createDirectory(atPath: requestDir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: requestFile) {
            FileManager.default.createFile(atPath: requestFile, contents: nil)
        }

        startWatchingFile()

        // Also poll every 0.5s as a fallback — DispatchSource can miss writes
        // from external processes that replace the file atomically.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkRequest()
            }
        }
    }

    func stop() {
        fileSource?.cancel()
        fileSource = nil
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func startWatchingFile() {
        fileSource?.cancel()

        let fd = open(requestFile, O_EVTONLY)
        guard fd >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .attrib],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            self?.checkRequest()
            // If the file was replaced (atomic write), re-watch it
            if let self = self {
                self.startWatchingFile()
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        fileSource = src
    }

    private func checkRequest() {
        guard let content = try? String(contentsOfFile: requestFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else { return }

        // Clear the file immediately
        try? "".write(toFile: requestFile, atomically: false, encoding: .utf8)

        // Handle each line as a file path
        for line in content.components(separatedBy: .newlines) {
            let path = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { continue }
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else { continue }
            handler?(url)
        }
    }
}
