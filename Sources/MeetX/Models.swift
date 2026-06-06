import Foundation

enum NotificationAction: String {
    case record = "record"
    case dismiss = "dismiss"
}

enum NotificationCategory: String {
    case meeting = "meeting"
}

enum MeetingKind: String, Codable {
    case zoom
    case googleMeet
    case manual
}

struct MeetingCandidate: Codable, Equatable {
    let id: String
    let kind: MeetingKind
    let displayName: String
    let url: String?
    let detectedAt: Date

    var safeName: String {
        displayName
            .replacingOccurrences(of: "[^A-Za-z0-9._-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    var hasMeaningfulTitle: Bool {
        let normalized = safeName.lowercased()
        guard !normalized.isEmpty else { return false }
        return kind != .manual &&
            normalized != "google-meet" &&
            normalized != "zoom-meeting" &&
            normalized != "manual-meeting"
    }

    var userInfo: [String: Any] {
        [
            "id": id,
            "kind": kind.rawValue,
            "displayName": displayName,
            "url": url as Any,
            "detectedAt": detectedAt.timeIntervalSince1970
        ]
    }

    static func manual() -> MeetingCandidate {
        MeetingCandidate(id: "manual-\(UUID().uuidString)", kind: .manual, displayName: "Manual Meeting", url: nil, detectedAt: Date())
    }

    init(id: String, kind: MeetingKind, displayName: String, url: String?, detectedAt: Date) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.url = url
        self.detectedAt = detectedAt
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let id = userInfo["id"] as? String,
              let kindValue = userInfo["kind"] as? String,
              let kind = MeetingKind(rawValue: kindValue),
              let displayName = userInfo["displayName"] as? String else {
            return nil
        }
        let url = userInfo["url"] as? String
        let detectedAt = Date(timeIntervalSince1970: userInfo["detectedAt"] as? TimeInterval ?? Date().timeIntervalSince1970)
        self.init(id: id, kind: kind, displayName: displayName, url: url, detectedAt: detectedAt)
    }
}

struct RecordingResult {
    let meeting: MeetingCandidate
    let startedAt: Date
    let endedAt: Date
    let audioURL: URL
}

struct ProcessedMeeting {
    let folder: URL
    let transcript: String
    let summary: String
    let notes: String
}
