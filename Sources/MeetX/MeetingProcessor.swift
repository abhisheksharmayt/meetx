import Foundation

final class MeetingProcessor {
    private let openAI: OpenAIClient
    private let artifactWriter: ArtifactWriter

    init(openAI: OpenAIClient, artifactWriter: ArtifactWriter) {
        self.openAI = openAI
        self.artifactWriter = artifactWriter
    }

    func process(result: RecordingResult) throws -> ProcessedMeeting {
        let folder = try artifactWriter.createFolder(for: result)
        EventLogger.log("Created meeting folder: \(folder.path)")
        try artifactWriter.copyRecording(from: result.audioURL, to: folder)
        EventLogger.log("Copied recording into meeting folder")

        do {
            let transcript = try openAI.transcribe(audioURL: result.audioURL)
            EventLogger.log("Transcription completed")
            try artifactWriter.write(transcript: transcript, to: folder)
            let summaryResult = try openAI.summarize(transcript: transcript)
            EventLogger.log("Summary completed")
            try artifactWriter.write(summary: summaryResult.summary, notes: summaryResult.notes, to: folder)
            try artifactWriter.writeMetadata(result: result, folder: folder, status: "completed", error: nil)
            return ProcessedMeeting(folder: folder, transcript: transcript, summary: summaryResult.summary, notes: summaryResult.notes)
        } catch {
            EventLogger.log("OpenAI processing failed; recording kept: \(error.localizedDescription)")
            try artifactWriter.writeMetadata(result: result, folder: folder, status: "failed", error: error.localizedDescription)
            try artifactWriter.writeError(error, to: folder)
            return ProcessedMeeting(folder: folder, transcript: "", summary: "", notes: "")
        }
    }

    func saveInterrupted(result: RecordingResult, reason: String) throws -> URL {
        let folder = try artifactWriter.createFolder(for: result)
        try artifactWriter.copyRecording(from: result.audioURL, to: folder)
        try artifactWriter.writeInterrupted(reason: reason, to: folder)
        try artifactWriter.writeMetadata(result: result, folder: folder, status: "interrupted", error: reason)
        return folder
    }
}

final class ArtifactWriter {
    private let fileManager = FileManager.default
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()

    func createFolder(for result: RecordingResult) throws -> URL {
        let desktop = try fileManager.url(for: .desktopDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let base = desktop.appendingPathComponent("MeetX Meetings", isDirectory: true)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        let timestamp = dateFormatter.string(from: result.startedAt)
        let meetingName = result.meeting.safeName.isEmpty ? "Meeting" : result.meeting.safeName
        let name = result.meeting.hasMeaningfulTitle ? "\(meetingName)_\(timestamp)" : "\(timestamp)_\(meetingName)"
        let folder = base.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func copyRecording(from source: URL, to folder: URL) throws {
        let destination = folder.appendingPathComponent("recording.m4a")
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    func write(transcript: String, to folder: URL) throws {
        try transcript.write(to: folder.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)
    }

    func write(summary: String, notes: String, to folder: URL) throws {
        try summary.write(to: folder.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)
        try notes.write(to: folder.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
    }

    func writeError(_ error: Error, to folder: URL) throws {
        try "Processing failed:\n\(error.localizedDescription)\n".write(to: folder.appendingPathComponent("error.txt"), atomically: true, encoding: .utf8)
    }

    func writeInterrupted(reason: String, to folder: URL) throws {
        let text = """
        # Recording Saved

        MeetX stopped this recording before transcription could run.

        Reason: \(reason)

        The raw audio is saved as `recording.m4a`.
        """
        try text.write(to: folder.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
    }

    func writeMetadata(result: RecordingResult, folder: URL, status: String, error: String?) throws {
        let metadata: [String: Any] = [
            "status": status,
            "error": error as Any,
            "meeting": [
                "id": result.meeting.id,
                "kind": result.meeting.kind.rawValue,
                "displayName": result.meeting.displayName,
                "url": result.meeting.url as Any
            ],
            "startedAt": ISO8601DateFormatter().string(from: result.startedAt),
            "endedAt": ISO8601DateFormatter().string(from: result.endedAt)
        ]
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: folder.appendingPathComponent("metadata.json"), options: .atomic)
    }
}
