import AppKit

final class NotchPromptController {
    private var panel: NSPanel?
    private var dismissTimer: Timer?

    func show(meeting: MeetingCandidate, onStart: @escaping () -> Void) {
        dismissTimer?.invalidate()
        panel?.close()

        let width: CGFloat = 350
        let height: CGFloat = 58
        let frame = Self.notchFrame(width: width, height: height)
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.hasShadow = true

        let view = NotchPromptView(meeting: meeting, onStart: { [weak self] in
            self?.dismiss()
            onStart()
        }, onDismiss: { [weak self] in
            self?.dismiss()
        })
        panel.contentView = view
        panel.orderFrontRegardless()
        self.panel = panel

        dismissTimer = Timer.scheduledTimer(withTimeInterval: 14, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        panel?.close()
        panel = nil
    }

    private static func notchFrame(width: CGFloat, height: CGFloat) -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = visible.midX - width / 2
        let y = visible.maxY - height - 8
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

private final class NotchPromptView: NSView {
    private let meeting: MeetingCandidate
    private let onStart: () -> Void
    private let onDismiss: () -> Void

    init(meeting: MeetingCandidate, onStart: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.meeting = meeting
        self.onStart = onStart
        self.onDismiss = onDismiss
        super.init(frame: .zero)
        wantsLayer = true
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLayer() {
        layer?.backgroundColor = NSColor(calibratedWhite: 0.055, alpha: 0.96).cgColor
        layer?.cornerRadius = 24
        layer?.cornerCurve = .continuous
        layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.10).cgColor
        layer?.borderWidth = 1
    }

    private func buildUI() {
        let icon = NSImageView()
        icon.image = Self.voiceIcon()
        icon.contentTintColor = .white
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Start transcribing?")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .white
        title.lineBreakMode = .byTruncatingTail

        let subtitle = NSTextField(labelWithString: meeting.displayName)
        subtitle.font = .systemFont(ofSize: 11, weight: .regular)
        subtitle.textColor = NSColor.white.withAlphaComponent(0.56)
        subtitle.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [title, subtitle])
        textStack.orientation = .vertical
        textStack.spacing = 3
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let startButton = NSButton(title: "Start", target: self, action: #selector(startPressed))
        startButton.bezelStyle = .rounded
        startButton.keyEquivalent = "\r"
        startButton.translatesAutoresizingMaskIntoConstraints = false

        let dismissButton = NSButton(title: "×", target: self, action: #selector(dismissPressed))
        dismissButton.bezelStyle = .inline
        dismissButton.font = .systemFont(ofSize: 16, weight: .medium)
        dismissButton.contentTintColor = NSColor.white.withAlphaComponent(0.72)
        dismissButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(textStack)
        addSubview(startButton)
        addSubview(dismissButton)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),

            textStack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: startButton.leadingAnchor, constant: -14),

            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            dismissButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            dismissButton.widthAnchor.constraint(equalToConstant: 26),
            dismissButton.heightAnchor.constraint(equalToConstant: 26),

            startButton.trailingAnchor.constraint(equalTo: dismissButton.leadingAnchor, constant: -6),
            startButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            startButton.widthAnchor.constraint(equalToConstant: 60)
        ])
    }

    private static func voiceIcon() -> NSImage? {
        let bundleURL = Bundle.main.url(forResource: "voice-svgrepo-com", withExtension: "svg")
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("voice-svgrepo-com.svg")
        let image = [bundleURL, rootURL].compactMap { $0 }.compactMap { NSImage(contentsOf: $0) }.first
        image?.isTemplate = true
        return image
    }

    @objc private func startPressed() {
        onStart()
    }

    @objc private func dismissPressed() {
        onDismiss()
    }
}
