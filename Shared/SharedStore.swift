import Foundation

struct ClipboardEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var text: String
    var createdAt: Date = Date()
    var isPinned: Bool = false
}

final class SharedStore {
    static let shared = SharedStore()
    static let appGroupID = "group.com.robin9094707.GeileTastatur"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        defaults = UserDefaults(suiteName: Self.appGroupID) ?? .standard
        registerDefaults()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            "numberRowEnabled": false,
            "aiSuggestionsEnabled": false,
            "cleanupTranscriptEnabled": true,
            "hapticsEnabled": true,
            "bridgeActive": false,
            "voiceRecording": false,
            "voiceCommand": "",
            "voiceCommandNonce": "",
            "transcriptNonce": "",
            "lastTranscript": "",
            "textModel": "gpt-6-luna",
            "transcriptionModel": "gpt-transcribe"
        ])
    }

    var apiKey: String {
        get { defaults.string(forKey: "openAIAPIKey") ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "openAIAPIKey") }
    }

    var numberRowEnabled: Bool {
        get { defaults.bool(forKey: "numberRowEnabled") }
        set { defaults.set(newValue, forKey: "numberRowEnabled") }
    }

    var aiSuggestionsEnabled: Bool {
        get { defaults.bool(forKey: "aiSuggestionsEnabled") }
        set { defaults.set(newValue, forKey: "aiSuggestionsEnabled") }
    }

    var cleanupTranscriptEnabled: Bool {
        get { defaults.bool(forKey: "cleanupTranscriptEnabled") }
        set { defaults.set(newValue, forKey: "cleanupTranscriptEnabled") }
    }

    var hapticsEnabled: Bool {
        get { defaults.bool(forKey: "hapticsEnabled") }
        set { defaults.set(newValue, forKey: "hapticsEnabled") }
    }

    var textModel: String {
        get { defaults.string(forKey: "textModel") ?? "gpt-6-luna" }
        set { defaults.set(newValue, forKey: "textModel") }
    }

    var transcriptionModel: String {
        get { defaults.string(forKey: "transcriptionModel") ?? "gpt-transcribe" }
        set { defaults.set(newValue, forKey: "transcriptionModel") }
    }

    var bridgeActive: Bool {
        get { defaults.bool(forKey: "bridgeActive") }
        set { defaults.set(newValue, forKey: "bridgeActive") }
    }

    var voiceRecording: Bool {
        get { defaults.bool(forKey: "voiceRecording") }
        set { defaults.set(newValue, forKey: "voiceRecording") }
    }

    var voiceCommand: String {
        defaults.string(forKey: "voiceCommand") ?? ""
    }

    var voiceCommandNonce: String {
        defaults.string(forKey: "voiceCommandNonce") ?? ""
    }

    var transcriptNonce: String {
        defaults.string(forKey: "transcriptNonce") ?? ""
    }

    var lastTranscript: String {
        defaults.string(forKey: "lastTranscript") ?? ""
    }

    func sendVoiceToggle() {
        defaults.set("toggle", forKey: "voiceCommand")
        defaults.set(UUID().uuidString, forKey: "voiceCommandNonce")
    }

    func sendVoiceCancel() {
        defaults.set("cancel", forKey: "voiceCommand")
        defaults.set(UUID().uuidString, forKey: "voiceCommandNonce")
    }

    func publishTranscript(_ text: String) {
        defaults.set(text, forKey: "lastTranscript")
        defaults.set(UUID().uuidString, forKey: "transcriptNonce")
    }

    func clearTranscript() {
        defaults.set("", forKey: "lastTranscript")
    }

    var clipboardEntries: [ClipboardEntry] {
        get {
            guard let data = defaults.data(forKey: "clipboardEntries"),
                  let decoded = try? decoder.decode([ClipboardEntry].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            let trimmed = Array(newValue.prefix(100))
            if let data = try? encoder.encode(trimmed) {
                defaults.set(data, forKey: "clipboardEntries")
            }
        }
    }

    func addClipboardText(_ text: String, pinned: Bool = false) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        var items = clipboardEntries
        if let index = items.firstIndex(where: { $0.text == clean }) {
            var existing = items.remove(at: index)
            existing.createdAt = Date()
            existing.isPinned = existing.isPinned || pinned
            items.insert(existing, at: 0)
        } else {
            items.insert(ClipboardEntry(text: clean, isPinned: pinned), at: 0)
        }
        clipboardEntries = items.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return $0.createdAt > $1.createdAt
        }
    }

    func togglePin(id: UUID) {
        var items = clipboardEntries
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned.toggle()
        clipboardEntries = items.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return $0.createdAt > $1.createdAt
        }
    }

    func deleteClipboard(id: UUID) {
        clipboardEntries.removeAll { $0.id == id }
    }

    func clearUnpinnedClipboard() {
        clipboardEntries = clipboardEntries.filter(\.isPinned)
    }
}
