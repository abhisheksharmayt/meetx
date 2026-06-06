import Foundation

enum EventLogger {
    static func log(_ message: String) {
        guard let root = try? FileManager.default.url(for: .desktopDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("MeetX Meetings", isDirectory: true) else {
            return
        }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        let url = root.appendingPathComponent("meetx.log")
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
