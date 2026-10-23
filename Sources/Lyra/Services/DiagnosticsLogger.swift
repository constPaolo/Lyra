import Foundation

enum DiagnosticsLogger {
    private static let queue = DispatchQueue(label: "lyra.diagnostics.logger")
    private static let enabledKey = "lyra.diagnosticsLoggingEnabled"

    static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: enabledKey) == nil {
            return true
        }
        return defaults.bool(forKey: enabledKey)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
    }

    static func log(_ message: String, category: String = "app") {
        guard isEnabled else { return }
        queue.async {
            write("[\(category)] \(message)")
        }
    }

    static func logSync(_ message: String, category: String = "app") {
        guard isEnabled else { return }
        queue.sync {
            write("[\(category)] \(message)")
        }
    }

    static func logFileURL() -> URL? {
        guard let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = logsDir.appendingPathComponent("Logs", isDirectory: true).appendingPathComponent("Lyra", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("lyra.log")
    }

    private static func write(_ line: String) {
        guard let url = logFileURL() else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let payload = "\(timestamp) \(line)\n"
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(payload.utf8))
                return
            }
        }
        try? payload.write(to: url, atomically: true, encoding: .utf8)
    }
}
