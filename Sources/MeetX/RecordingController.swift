import AppKit
import Foundation

final class RecordingController {
    var onStateChange: (() -> Void)?
    var onCompleted: ((URL) -> Void)?
    var currentMeetingTitle: String? { currentMeeting?.displayName }

    private let processor: MeetingProcessor
    private var recorder: AudioRecorder?
    private var currentMeeting: MeetingCandidate?
    private var startedAt: Date?
    private(set) var isProcessing = false

    var isRecording: Bool { recorder?.isRecording == true }

    var statusText: String {
        if isProcessing { return "Processing meeting..." }
        if isRecording, let startedAt {
            let seconds = Int(Date().timeIntervalSince(startedAt))
            return "Recording \(seconds / 60)m \(seconds % 60)s"
        }
        return "Idle"
    }

    init(processor: MeetingProcessor) {
        self.processor = processor
    }

    func start(meeting: MeetingCandidate) {
        guard !isRecording else { return }
        EventLogger.log("Starting recording: \(meeting.displayName) [\(meeting.id)]")
        currentMeeting = meeting
        startedAt = Date()
        let recorder = AudioRecorder()
        self.recorder = recorder
        do {
            try recorder.start()
        } catch {
            EventLogger.log("Recording start failed: \(error.localizedDescription)")
            presentError("Could not start recording: \(error.localizedDescription)")
            self.recorder = nil
            currentMeeting = nil
            startedAt = nil
        }
        onStateChange?()
    }

    func meetingDidEnd(_ meeting: MeetingCandidate) {
        guard isRecording, meeting.id == currentMeeting?.id else { return }
        guard currentMeeting?.kind != .manual else { return }
        EventLogger.log("Detected meeting ended, stopping: \(meeting.displayName) [\(meeting.id)]")
        stopAndProcess()
    }

    func stopAndProcess() {
        guard !isProcessing, let recorder, let currentMeeting, let startedAt else { return }
        EventLogger.log("Stopping recording for processing: \(currentMeeting.displayName) [\(currentMeeting.id)]")
        self.recorder = nil
        self.currentMeeting = nil
        self.startedAt = nil
        isProcessing = true
        onStateChange?()

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let audioURL = try recorder.stop()
                EventLogger.log("Audio stopped and saved to temp file: \(audioURL.path)")
                let result = RecordingResult(meeting: currentMeeting, startedAt: startedAt, endedAt: Date(), audioURL: audioURL)
                let processed = try self.processor.process(result: result)
                DispatchQueue.main.async {
                    EventLogger.log("Meeting folder ready: \(processed.folder.path)")
                    self.isProcessing = false
                    self.onCompleted?(processed.folder)
                    self.onStateChange?()
                }
            } catch {
                DispatchQueue.main.async {
                    EventLogger.log("Recording processing failed before folder completion: \(error.localizedDescription)")
                    self.isProcessing = false
                    self.presentError("Processing failed: \(error.localizedDescription)")
                    self.onStateChange?()
                }
            }
        }
    }

    func stopManually() {
        stopAndProcess()
    }

    @discardableResult
    func stopAndSaveInterrupted(reason: String) -> URL? {
        guard let recorder, let currentMeeting, let startedAt else { return nil }
        EventLogger.log("Interrupted recording stop: \(reason)")
        self.recorder = nil
        self.currentMeeting = nil
        self.startedAt = nil
        onStateChange?()

        do {
            let audioURL = try recorder.stop()
            let result = RecordingResult(meeting: currentMeeting, startedAt: startedAt, endedAt: Date(), audioURL: audioURL)
            let folder = try processor.saveInterrupted(result: result, reason: reason)
            onCompleted?(folder)
            return folder
        } catch {
            presentError("Could not save interrupted recording: \(error.localizedDescription)")
            return nil
        }
    }

    private func presentError(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "MeetX"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}
