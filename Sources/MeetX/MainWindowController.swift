import AppKit
import Foundation

struct MeetingRecord {
    let folder: URL
    let title: String
    let modifiedAt: Date

    var summaryURL: URL { folder.appendingPathComponent("summary.md") }
    var notesURL: URL { folder.appendingPathComponent("notes.md") }
    var transcriptURL: URL { folder.appendingPathComponent("transcript.txt") }

    func text(for section: DetailSection) -> String {
        let url: URL
        switch section {
        case .summary: url = summaryURL
        case .notes: url = notesURL
        case .transcript: url = transcriptURL
        case .settings: return ""
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "No \(section.title.lowercased()) file found for this meeting."
    }
}

enum DetailSection: Int {
    case summary = 0
    case notes = 1
    case transcript = 2
    case settings = 3

    var title: String {
        switch self {
        case .summary: return "Summary"
        case .notes: return "Notes"
        case .transcript: return "Transcript"
        case .settings: return "Settings"
        }
    }
}

final class MeetingLibrary {
    private let fileManager = FileManager.default

    var rootFolder: URL? {
        guard let desktop = try? fileManager.url(for: .desktopDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return nil
        }
        return desktop.appendingPathComponent("MeetX Meetings", isDirectory: true)
    }

    func records() -> [MeetingRecord] {
        guard let rootFolder else { return [] }
        let folders = (try? fileManager.contentsOfDirectory(at: rootFolder, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey])) ?? []
        return folders.compactMap { folder in
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let modified = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return MeetingRecord(folder: folder, title: folder.lastPathComponent, modifiedAt: modified)
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }
}

final class MainWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    var onStopRecording: (() -> Void)?

    private let settings: SettingsStore
    private let library = MeetingLibrary()
    private var meetings: [MeetingRecord] = []
    private var selectedSection: DetailSection = .summary

    private let tableView = NSTableView()
    private let titleLabel = NSTextField(labelWithString: "MeetX")
    private let detailSelector = NSSegmentedControl(labels: ["Summary", "Notes", "Transcript", "Settings"], trackingMode: .selectOne, target: nil, action: nil)
    private let textView = NSTextView()
    private let textScroll = NSScrollView()
    private let settingsView = NSStackView()
    private let apiKeyField = NSSecureTextField()
    private let summaryModelField = NSTextField()
    private let transcriptionModelField = NSTextField()
    private let recordingStatusLabel = NSTextField(labelWithString: "Idle")
    private let stopRecordingButton = NSButton(title: "Stop Transcribing", target: nil, action: nil)

    init(settings: SettingsStore) {
        self.settings = settings
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MeetX"
        super.init(window: window)
        buildUI()
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        refresh()
        window?.centerIfNeeded()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettings() {
        show()
        detailSelector.selectedSegment = DetailSection.settings.rawValue
        selectedSection = .settings
        renderSelection()
        window?.makeFirstResponder(apiKeyField)
    }

    func refresh(selecting folder: URL? = nil) {
        meetings = library.records()
        tableView.reloadData()
        if let folder, let index = meetings.firstIndex(where: { $0.folder.path == folder.path }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else if tableView.selectedRow < 0, !meetings.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        renderSelection()
    }

    func setRecordingState(status: String, isRecording: Bool, isProcessing: Bool, meetingTitle: String?) {
        if isRecording {
            recordingStatusLabel.stringValue = meetingTitle.map { "Listening: \($0)" } ?? status
        } else {
            recordingStatusLabel.stringValue = status
        }
        recordingStatusLabel.textColor = isRecording ? .systemRed : .secondaryLabelColor
        stopRecordingButton.isHidden = !isRecording
        stopRecordingButton.isEnabled = isRecording && !isProcessing
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true

        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(split)

        let sidebar = NSView()
        let detail = NSView()
        split.addArrangedSubview(sidebar)
        split.addArrangedSubview(detail)

        buildSidebar(in: sidebar)
        buildDetail(in: detail)

        NSLayoutConstraint.activate([
            split.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            split.topAnchor.constraint(equalTo: content.topAnchor),
            split.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 280)
        ])
    }

    private func buildSidebar(in view: NSView) {
        let label = NSTextField(labelWithString: "Meetings")
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false

        let refresh = NSButton(title: "Refresh", target: self, action: #selector(refreshButtonPressed))
        refresh.bezelStyle = .rounded
        refresh.translatesAutoresizingMaskIntoConstraints = false

        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("meeting"))
        tableColumn.title = "Meeting"
        tableView.addTableColumn(tableColumn)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 44

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(label)
        view.addSubview(refresh)
        view.addSubview(recordingStatusLabel)
        view.addSubview(stopRecordingButton)
        view.addSubview(scroll)

        recordingStatusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        recordingStatusLabel.lineBreakMode = .byTruncatingTail
        recordingStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        stopRecordingButton.target = self
        stopRecordingButton.action = #selector(stopRecordingPressed)
        stopRecordingButton.bezelStyle = .rounded
        stopRecordingButton.translatesAutoresizingMaskIntoConstraints = false
        stopRecordingButton.isHidden = true

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            label.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            refresh.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            refresh.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            recordingStatusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            recordingStatusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            recordingStatusLabel.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 12),
            stopRecordingButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stopRecordingButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stopRecordingButton.topAnchor.constraint(equalTo: recordingStatusLabel.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: stopRecordingButton.bottomAnchor, constant: 12),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func buildDetail(in view: NSView) {
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        detailSelector.target = self
        detailSelector.action = #selector(sectionChanged)
        detailSelector.selectedSegment = selectedSection.rawValue
        detailSelector.translatesAutoresizingMaskIntoConstraints = false

        let openFolder = NSButton(title: "Open Folder", target: self, action: #selector(openSelectedFolder))
        openFolder.bezelStyle = .rounded
        openFolder.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textScroll.documentView = textView
        textScroll.hasVerticalScroller = true
        textScroll.translatesAutoresizingMaskIntoConstraints = false

        buildSettingsView()
        settingsView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleLabel)
        view.addSubview(openFolder)
        view.addSubview(detailSelector)
        view.addSubview(textScroll)
        view.addSubview(settingsView)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: openFolder.leadingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            openFolder.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            openFolder.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            detailSelector.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailSelector.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            textScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            textScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            textScroll.topAnchor.constraint(equalTo: detailSelector.bottomAnchor, constant: 16),
            textScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            settingsView.leadingAnchor.constraint(equalTo: textScroll.leadingAnchor),
            settingsView.trailingAnchor.constraint(lessThanOrEqualTo: textScroll.trailingAnchor),
            settingsView.topAnchor.constraint(equalTo: textScroll.topAnchor)
        ])
    }

    private func buildSettingsView() {
        settingsView.orientation = .vertical
        settingsView.spacing = 12
        settingsView.alignment = .leading

        let heading = NSTextField(labelWithString: "Settings")
        heading.font = .systemFont(ofSize: 18, weight: .semibold)
        settingsView.addArrangedSubview(heading)
        settingsView.addArrangedSubview(row(label: "OpenAI API Key", field: apiKeyField))
        settingsView.addArrangedSubview(row(label: "Summary Model", field: summaryModelField))
        settingsView.addArrangedSubview(row(label: "Transcription Model", field: transcriptionModelField))

        let save = NSButton(title: "Save Settings", target: self, action: #selector(saveSettings))
        save.bezelStyle = .rounded
        settingsView.addArrangedSubview(save)
    }

    private func row(label: String, field: NSTextField) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 12
        let labelView = NSTextField(labelWithString: label)
        labelView.widthAnchor.constraint(equalToConstant: 150).isActive = true
        field.widthAnchor.constraint(equalToConstant: 360).isActive = true
        stack.addArrangedSubview(labelView)
        stack.addArrangedSubview(field)
        return stack
    }

    private func renderSelection() {
        apiKeyField.placeholderString = settings.hasCachedOpenAIAPIKey ? "Key saved for this session; paste a new key to update" : "Paste OpenAI API key"
        if selectedSection == .settings, !apiKeyField.currentEditorExists {
            apiKeyField.stringValue = ""
        }
        summaryModelField.stringValue = settings.summaryModel
        transcriptionModelField.stringValue = settings.transcriptionModel

        let isSettings = selectedSection == .settings
        textScroll.isHidden = isSettings
        settingsView.isHidden = !isSettings

        guard !isSettings else {
            titleLabel.stringValue = "MeetX Settings"
            return
        }

        guard let record = selectedRecord else {
            titleLabel.stringValue = "No meetings yet"
            textView.string = "Recorded meetings will appear here after MeetX creates files in ~/Desktop/MeetX Meetings."
            return
        }

        titleLabel.stringValue = record.title
        textView.string = record.text(for: selectedSection)
    }

    private var selectedRecord: MeetingRecord? {
        let row = tableView.selectedRow
        guard row >= 0, row < meetings.count else { return nil }
        return meetings[row]
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        meetings.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("MeetingCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier
        let textField = cell.textField ?? NSTextField(labelWithString: "")
        textField.lineBreakMode = .byTruncatingTail
        textField.font = .systemFont(ofSize: 13, weight: .medium)
        textField.translatesAutoresizingMaskIntoConstraints = false
        if cell.textField == nil {
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        textField.stringValue = meetings[row].title
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        renderSelection()
    }

    @objc private func refreshButtonPressed() {
        refresh()
    }

    @objc private func sectionChanged() {
        selectedSection = DetailSection(rawValue: detailSelector.selectedSegment) ?? .summary
        renderSelection()
    }

    @objc private func openSelectedFolder() {
        if let selectedRecord {
            NSWorkspace.shared.open(selectedRecord.folder)
        } else if let root = library.rootFolder {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            NSWorkspace.shared.open(root)
        }
    }

    @objc private func saveSettings() {
        if !apiKeyField.stringValue.isEmpty {
            settings.openAIAPIKey = apiKeyField.stringValue
        }
        settings.summaryModel = summaryModelField.stringValue.isEmpty ? "gpt-5.5" : summaryModelField.stringValue
        settings.transcriptionModel = transcriptionModelField.stringValue.isEmpty ? "gpt-4o-transcribe" : transcriptionModelField.stringValue
        renderSelection()
    }

    @objc private func stopRecordingPressed() {
        onStopRecording?()
    }
}

private extension NSTextField {
    var currentEditorExists: Bool {
        currentEditor() != nil
    }
}

private extension NSWindow {
    func centerIfNeeded() {
        if frame.origin == .zero {
            center()
        }
    }
}
