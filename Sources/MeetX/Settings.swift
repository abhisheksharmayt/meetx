import AppKit
import Foundation
import Security

final class SettingsStore {
    private let defaults = UserDefaults.standard
    private let service = "com.meetx.recorder"
    private let apiKeyAccount = "openai-api-key"
    private var cachedOpenAIAPIKey: String?
    private var didAttemptKeychainRead = false

    var summaryModel: String {
        get { defaults.string(forKey: "summaryModel") ?? "gpt-5.5" }
        set { defaults.set(newValue, forKey: "summaryModel") }
    }

    var transcriptionModel: String {
        get { defaults.string(forKey: "transcriptionModel") ?? "gpt-4o-transcribe" }
        set { defaults.set(newValue, forKey: "transcriptionModel") }
    }

    var openAIAPIKey: String? {
        get {
            if didAttemptKeychainRead {
                return cachedOpenAIAPIKey
            }
            didAttemptKeychainRead = true
            cachedOpenAIAPIKey = readPassword(account: apiKeyAccount)
            return cachedOpenAIAPIKey
        }
        set {
            if let newValue, !newValue.isEmpty {
                savePassword(newValue, account: apiKeyAccount)
                cachedOpenAIAPIKey = newValue
                didAttemptKeychainRead = true
            } else {
                deletePassword(account: apiKeyAccount)
                cachedOpenAIAPIKey = nil
                didAttemptKeychainRead = true
            }
        }
    }

    var hasCachedOpenAIAPIKey: Bool {
        cachedOpenAIAPIKey?.isEmpty == false
    }

    private func readPassword(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func savePassword(_ password: String, account: String) {
        deletePassword(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(password.utf8)
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func deletePassword(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private let apiKeyField = NSSecureTextField()
    private let summaryModelField = NSTextField()
    private let transcriptionModelField = NSTextField()
    private var settings: SettingsStore?

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 220), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "MeetX Settings"
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(settings: SettingsStore) {
        self.settings = settings
        apiKeyField.placeholderString = "Paste a new key to update"
        apiKeyField.stringValue = ""
        summaryModelField.stringValue = settings.summaryModel
        transcriptionModelField.stringValue = settings.transcriptionModel
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeFirstResponder(apiKeyField)
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        stack.addArrangedSubview(row(label: "OpenAI API Key", field: apiKeyField))
        stack.addArrangedSubview(row(label: "Summary Model", field: summaryModelField))
        stack.addArrangedSubview(row(label: "Transcription Model", field: transcriptionModelField))

        let save = NSButton(title: "Save", target: self, action: #selector(save))
        save.bezelStyle = .rounded
        stack.addArrangedSubview(save)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20)
        ])
    }

    private func row(label: String, field: NSTextField) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 12
        let labelView = NSTextField(labelWithString: label)
        labelView.widthAnchor.constraint(equalToConstant: 140).isActive = true
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 260).isActive = true
        stack.addArrangedSubview(labelView)
        stack.addArrangedSubview(field)
        return stack
    }

    @objc private func save() {
        if !apiKeyField.stringValue.isEmpty {
            settings?.openAIAPIKey = apiKeyField.stringValue
        }
        settings?.summaryModel = summaryModelField.stringValue.isEmpty ? "gpt-5.5" : summaryModelField.stringValue
        settings?.transcriptionModel = transcriptionModelField.stringValue.isEmpty ? "gpt-4o-transcribe" : transcriptionModelField.stringValue
        window?.close()
    }
}
