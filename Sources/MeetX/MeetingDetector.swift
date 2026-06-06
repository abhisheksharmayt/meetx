import AppKit
import Foundation

final class MeetingDetector {
    var onMeetingDetected: ((MeetingCandidate) -> Void)?
    var onMeetingEnded: ((MeetingCandidate) -> Void)?

    private var timer: Timer?
    private var lastPrompted: [String: Date] = [:]
    private var activeMeeting: MeetingCandidate?
    private let promptCooldown: TimeInterval = 10 * 60

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.scan()
        }
        scan()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func scan() {
        let detected = detectGoogleMeet() ?? detectZoom()
        if let detected {
            if let activeMeeting, activeMeeting.id != detected.id {
                onMeetingEnded?(activeMeeting)
            }
            activeMeeting = detected
            if shouldPrompt(detected) {
                lastPrompted[detected.id] = Date()
                onMeetingDetected?(detected)
            }
        } else if let activeMeeting {
            self.activeMeeting = nil
            onMeetingEnded?(activeMeeting)
        }
    }

    private func shouldPrompt(_ meeting: MeetingCandidate) -> Bool {
        guard let last = lastPrompted[meeting.id] else { return true }
        return Date().timeIntervalSince(last) > promptCooldown
    }

    private func detectZoom() -> MeetingCandidate? {
        let zoomRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "us.zoom.xos"
        }
        guard zoomRunning else { return nil }
        let active = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "us.zoom.xos"
        guard active else { return nil }
        return MeetingCandidate(
            id: "zoom-active",
            kind: .zoom,
            displayName: "Zoom Meeting",
            url: nil,
            detectedAt: Date()
        )
    }

    private func detectGoogleMeet() -> MeetingCandidate? {
        let browsers = [
            BrowserScript(appName: "Google Chrome", bundleIdentifier: "com.google.Chrome"),
            BrowserScript(appName: "Safari", bundleIdentifier: "com.apple.Safari"),
            BrowserScript(appName: "Microsoft Edge", bundleIdentifier: "com.microsoft.edgemac")
        ]

        for browser in browsers {
            guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == browser.bundleIdentifier }) else {
                continue
            }
            guard let tab = browser.meetTab() else {
                continue
            }
            guard let roomURL = GoogleMeetURL.roomURL(from: tab.url) else {
                continue
            }
            return MeetingCandidate(
                id: "meet-\(roomURL.absoluteString)",
                kind: .googleMeet,
                displayName: tab.title.isEmpty ? roomURL.lastPathComponent : tab.title,
                url: roomURL.absoluteString,
                detectedAt: Date()
            )
        }
        return nil
    }
}

private enum GoogleMeetURL {
    private static let roomCodePattern = #"^[a-z]{3}-[a-z]{4}-[a-z]{3}$"#

    static func roomURL(from rawURL: String) -> URL? {
        guard let components = URLComponents(string: rawURL),
              components.host == "meet.google.com" else {
            return nil
        }
        let pathParts = components.path.split(separator: "/").map(String.init)
        guard let roomCode = pathParts.first,
              roomCode.range(of: roomCodePattern, options: .regularExpression) != nil else {
            return nil
        }
        return URL(string: "https://meet.google.com/\(roomCode)")
    }
}

private struct BrowserTab {
    let title: String
    let url: String
}

private struct BrowserScript {
    let appName: String
    let bundleIdentifier: String

    func meetTab() -> BrowserTab? {
        let script: String
        if appName == "Safari" {
            script = """
            tell application "\(appName)"
              repeat with browserWindow in windows
                repeat with browserTab in tabs of browserWindow
                  set tabURL to URL of browserTab
                  if tabURL contains "meet.google.com/" then
                    set tabName to name of browserTab
                    return tabName & linefeed & tabURL
                  end if
                end repeat
              end repeat
              return ""
            end tell
            """
        } else {
            script = """
            tell application "\(appName)"
              repeat with browserWindow in windows
                repeat with browserTab in tabs of browserWindow
                  set tabURL to URL of browserTab
                  if tabURL contains "meet.google.com/" then
                    set tabName to title of browserTab
                    return tabName & linefeed & tabURL
                  end if
                end repeat
              end repeat
              return ""
            end tell
            """
        }

        var error: NSDictionary?
        guard let output = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue,
              error == nil else {
            return nil
        }
        let parts = output.components(separatedBy: .newlines)
        guard parts.count >= 2 else { return nil }
        return BrowserTab(title: parts[0], url: parts[1])
    }
}
