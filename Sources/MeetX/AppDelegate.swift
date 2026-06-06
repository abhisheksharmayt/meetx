import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let settings = SettingsStore()
    private lazy var artifactWriter = ArtifactWriter()
    private lazy var openAI = OpenAIClient(settings: settings)
    private lazy var processor = MeetingProcessor(openAI: openAI, artifactWriter: artifactWriter)
    private lazy var controller = RecordingController(processor: processor)
    private lazy var detector = MeetingDetector()
    private lazy var mainWindowController = MainWindowController(settings: settings)
    private lazy var notchPrompt = NotchPromptController()
    private var lastMeetingFolder: URL?
    private var lastDetectedMeeting: MeetingCandidate?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureApplicationMenu()
        configureMenu()
        configureNotifications()
        requestNotificationPermission()
        configureLifecycleObservers()

        controller.onStateChange = { [weak self] in
            self?.configureMenu()
            self?.refreshMainWindowRecordingState()
        }
        controller.onCompleted = { [weak self] folder in
            self?.lastMeetingFolder = folder
            self?.showCompletedNotification(folder: folder)
            self?.configureMenu()
            self?.refreshMainWindowRecordingState()
        }
        mainWindowController.onStopRecording = { [weak self] in
            self?.controller.stopManually()
            self?.configureMenu()
            self?.refreshMainWindowRecordingState()
        }
        refreshMainWindowRecordingState()

        detector.onMeetingDetected = { [weak self] meeting in
            self?.lastDetectedMeeting = meeting
            self?.configureMenu()
            self?.showRecordingPrompt(for: meeting)
        }
        detector.onMeetingEnded = { [weak self] meeting in
            self?.controller.meetingDidEnd(meeting)
        }
        detector.start()
        showMainWindow()
    }

    private func configureLifecycleObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
    }

    private func configureApplicationMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Show MeetX", action: #selector(showMainWindow), keyEquivalent: "0"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit MeetX", action: #selector(quit), keyEquivalent: "q"))
        for item in appMenu.items {
            item.target = self
        }
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func configureMenu() {
        if let button = statusItem.button {
            button.title = controller.isRecording ? "MeetX REC" : "MeetX"
        }

        let menu = NSMenu()
        let stateTitle = controller.statusText
        let state = NSMenuItem(title: stateTitle, action: nil, keyEquivalent: "")
        state.isEnabled = false
        menu.addItem(state)
        if let lastDetectedMeeting {
            let detected = NSMenuItem(title: "Detected: \(lastDetectedMeeting.displayName)", action: nil, keyEquivalent: "")
            detected.isEnabled = false
            menu.addItem(detected)
        }
        menu.addItem(.separator())

        if controller.isRecording {
            menu.addItem(NSMenuItem(title: "Stop & Summarize", action: #selector(stopRecording), keyEquivalent: "s"))
        } else {
            menu.addItem(NSMenuItem(title: "Start Manual Recording", action: #selector(startManualRecording), keyEquivalent: "r"))
        }

        menu.addItem(NSMenuItem(title: "Show MeetX", action: #selector(showMainWindow), keyEquivalent: "0"))
        menu.addItem(NSMenuItem(title: "Open Last Folder", action: #selector(openLastFolder), keyEquivalent: "o"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
    }

    private func configureNotifications() {
        let record = UNNotificationAction(identifier: NotificationAction.record.rawValue, title: "Start", options: [.foreground])
        let dismiss = UNNotificationAction(identifier: NotificationAction.dismiss.rawValue, title: "Dismiss", options: [])
        let category = UNNotificationCategory(identifier: NotificationCategory.meeting.rawValue, actions: [record, dismiss], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
        UNUserNotificationCenter.current().delegate = self
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func showRecordingPrompt(for meeting: MeetingCandidate) {
        guard !controller.isRecording else { return }
        let content = UNMutableNotificationContent()
        content.title = "Start transcribing?"
        content.body = "\(meeting.displayName) is active."
        content.categoryIdentifier = NotificationCategory.meeting.rawValue
        content.userInfo = meeting.userInfo
        let request = UNNotificationRequest(identifier: meeting.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)

        showVisibleRecordingPrompt(for: meeting)
    }

    private func showVisibleRecordingPrompt(for meeting: MeetingCandidate) {
        notchPrompt.show(meeting: meeting) { [weak self] in
            guard let self, !self.controller.isRecording else { return }
            self.controller.start(meeting: meeting)
            self.configureMenu()
        }
    }

    private func showCompletedNotification(folder: URL) {
        let content = UNMutableNotificationContent()
        content.title = "Meeting summary ready"
        content.body = folder.lastPathComponent
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        mainWindowController.refresh(selecting: folder)
    }

    @objc private func startManualRecording() {
        controller.start(meeting: .manual())
        configureMenu()
    }

    @objc private func stopRecording() {
        controller.stopManually()
        configureMenu()
        refreshMainWindowRecordingState()
    }

    @objc private func openLastFolder() {
        guard let folder = lastMeetingFolder else { return }
        NSWorkspace.shared.open(folder)
    }

    @objc private func openSettings() {
        mainWindowController.showSettings()
    }

    @objc private func showMainWindow() {
        mainWindowController.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func workspaceWillSleep() {
        _ = controller.stopAndSaveInterrupted(reason: "Mac is going to sleep or shutting down")
        configureMenu()
        refreshMainWindowRecordingState()
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = controller.stopAndSaveInterrupted(reason: "MeetX closed before processing finished")
    }

    private func refreshMainWindowRecordingState() {
        mainWindowController.setRecordingState(
            status: controller.statusText,
            isRecording: controller.isRecording,
            isProcessing: controller.isProcessing,
            meetingTitle: controller.currentMeetingTitle
        )
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == NotificationAction.record.rawValue,
              let meeting = MeetingCandidate(userInfo: response.notification.request.content.userInfo) else {
            return
        }
        await MainActor.run {
            controller.start(meeting: meeting)
            configureMenu()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
