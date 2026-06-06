import AVFoundation
import Foundation

final class AudioRecorder: NSObject {
    private let workDirectory: URL
    private let outputURL: URL
    private var recorder: AVAudioRecorder?
    private(set) var isRecording = false

    override init() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MeetX-\(UUID().uuidString)", isDirectory: true)
        workDirectory = directory
        outputURL = directory.appendingPathComponent("recording.m4a")
        super.init()
    }

    func start() throws {
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 96_000
        ]
        let recorder = try AVAudioRecorder(url: outputURL, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw NSError(domain: "MeetX", code: 1, userInfo: [NSLocalizedDescriptionKey: "Microphone recording did not start."])
        }
        self.recorder = recorder
        isRecording = true
    }

    func stop() throws -> URL {
        isRecording = false
        recorder?.stop()
        recorder = nil
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw NSError(domain: "MeetX", code: 2, userInfo: [NSLocalizedDescriptionKey: "No audio file was created."])
        }
        return outputURL
    }
}
