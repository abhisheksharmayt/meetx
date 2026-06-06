import AVFoundation
import Foundation

final class OpenAIClient {
    private let settings: SettingsStore
    private let session: URLSession
    private let baseURL = URL(string: "https://api.openai.com/v1")!

    init(settings: SettingsStore, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    func transcribe(audioURL: URL) throws -> String {
        guard let apiKey = settings.openAIAPIKey, !apiKey.isEmpty else {
            throw NSError(domain: "MeetX", code: 10, userInfo: [NSLocalizedDescriptionKey: "Set your OpenAI API key in Settings."])
        }
        let chunks = try AudioChunker.chunks(for: audioURL)
        var transcript = ""
        for (index, chunk) in chunks.enumerated() {
            let text = try transcribeChunk(chunk, apiKey: apiKey)
            transcript += "\n\n[Part \(index + 1)]\n\(text)"
        }
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func summarize(transcript: String) throws -> (summary: String, notes: String) {
        guard let apiKey = settings.openAIAPIKey, !apiKey.isEmpty else {
            throw NSError(domain: "MeetX", code: 10, userInfo: [NSLocalizedDescriptionKey: "Set your OpenAI API key in Settings."])
        }
        let prompt = """
        You are MeetX, a meeting summarizer. Create concise markdown from this transcript.

        Return exactly two top-level sections:
        # Summary
        Include purpose, key discussion points, decisions, blockers, and action items.

        # Notes
        Include detailed chronological notes with useful context.

        Transcript:
        \(transcript)
        """
        let requestBody: [String: Any] = [
            "model": settings.summaryModel,
            "input": prompt
        ]
        var request = URLRequest(url: baseURL.appendingPathComponent("responses"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let data = try perform(request)
        let text = try parseResponseText(data)
        return splitSummaryAndNotes(text)
    }

    private func transcribeChunk(_ url: URL, apiKey: String) throws -> String {
        let boundary = "MeetXBoundary-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appendingPathComponent("audio/transcriptions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendMultipartField(name: "model", value: settings.transcriptionModel, boundary: boundary)
        body.appendMultipartField(name: "response_format", value: "text", boundary: boundary)
        let fileData = try Data(contentsOf: url)
        body.appendMultipartFile(name: "file", filename: url.lastPathComponent, contentType: "audio/m4a", data: fileData, boundary: boundary)
        body.appendString("--\(boundary)--\r\n")
        request.httpBody = body

        let data = try perform(request)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func perform(_ request: URLRequest) throws -> Data {
        var responseData: Data?
        var responseValue: URLResponse?
        var responseError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        session.dataTask(with: request) { data, response, error in
            responseData = data
            responseValue = response
            responseError = error
            semaphore.signal()
        }.resume()
        semaphore.wait()

        if let responseError { throw responseError }
        guard let http = responseValue as? HTTPURLResponse else {
            throw NSError(domain: "MeetX", code: 20, userInfo: [NSLocalizedDescriptionKey: "No response from OpenAI."])
        }
        guard (200..<300).contains(http.statusCode), let responseData else {
            let message = responseData.flatMap { String(data: $0, encoding: .utf8) } ?? "OpenAI request failed."
            throw NSError(domain: "MeetX", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return responseData
    }

    private func parseResponseText(_ data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let outputText = object?["output_text"] as? String {
            return outputText
        }
        if let output = object?["output"] as? [[String: Any]] {
            let parts = output.flatMap { item -> [String] in
                guard let content = item["content"] as? [[String: Any]] else { return [] }
                return content.compactMap { $0["text"] as? String }
            }
            if !parts.isEmpty { return parts.joined(separator: "\n") }
        }
        throw NSError(domain: "MeetX", code: 21, userInfo: [NSLocalizedDescriptionKey: "Could not read summary response."])
    }

    private func splitSummaryAndNotes(_ text: String) -> (String, String) {
        guard let notesRange = text.range(of: "# Notes") else {
            return (text, "")
        }
        let summary = String(text[..<notesRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = String(text[notesRange.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (summary, notes)
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendString("\(value)\r\n")
    }

    mutating func appendMultipartFile(name: String, filename: String, contentType: String, data: Data, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: \(contentType)\r\n\r\n")
        append(data)
        appendString("\r\n")
    }
}

enum AudioChunker {
    private static let maxBytes = 24 * 1024 * 1024

    static func chunks(for audioURL: URL) throws -> [URL] {
        let size = try FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? NSNumber
        guard (size?.intValue ?? 0) > maxBytes else { return [audioURL] }

        let asset = AVURLAsset(url: audioURL)
        let duration = CMTimeGetSeconds(asset.duration)
        let partCount = max(2, Int(ceil(Double(size?.intValue ?? maxBytes) / Double(maxBytes))))
        let partDuration = duration / Double(partCount)
        var urls: [URL] = []

        for index in 0..<partCount {
            let start = CMTime(seconds: Double(index) * partDuration, preferredTimescale: 600)
            let endSeconds = index == partCount - 1 ? duration : Double(index + 1) * partDuration
            let range = CMTimeRange(start: start, end: CMTime(seconds: endSeconds, preferredTimescale: 600))
            let output = FileManager.default.temporaryDirectory.appendingPathComponent("MeetX-chunk-\(UUID().uuidString)-\(index).m4a")
            try export(asset: asset, range: range, output: output)
            urls.append(output)
        }
        return urls
    }

    private static func export(asset: AVAsset, range: CMTimeRange, output: URL) throws {
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(domain: "MeetX", code: 30, userInfo: [NSLocalizedDescriptionKey: "Could not create chunk exporter."])
        }
        exporter.timeRange = range
        exporter.outputURL = output
        exporter.outputFileType = .m4a
        let semaphore = DispatchSemaphore(value: 0)
        exporter.exportAsynchronously {
            semaphore.signal()
        }
        semaphore.wait()
        if exporter.status != .completed {
            throw exporter.error ?? NSError(domain: "MeetX", code: 31, userInfo: [NSLocalizedDescriptionKey: "Audio chunk export failed."])
        }
    }
}
