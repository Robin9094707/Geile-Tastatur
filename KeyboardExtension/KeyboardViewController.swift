import Combine
import SwiftUI
import UIKit

final class KeyboardControllerModel: ObservableObject {
    enum Page {
        case letters
        case symbols
    }

    @Published var page: Page = .letters
    @Published var isShifted = false
    @Published var numberRowEnabled = SharedStore.shared.numberRowEnabled
    @Published var aiSuggestionsEnabled = SharedStore.shared.aiSuggestionsEnabled
    @Published var suggestions: [String] = []
    @Published var clipboardEntries: [ClipboardEntry] = SharedStore.shared.clipboardEntries
    @Published var showClipboard = false
    @Published var bridgeActive = SharedStore.shared.bridgeActive
    @Published var recording = SharedStore.shared.voiceRecording
    @Published var statusMessage: String?
    @Published var isLoadingAI = false
    @Published var needsGlobeKey = true

    var insertText: (String) -> Void = { _ in }
    var deleteBackward: () -> Void = {}
    var nextKeyboard: () -> Void = {}
    var contextBeforeInput: () -> String = { "" }
    var currentPasteboardText: () -> String? = { nil }
    var playClick: () -> Void = {}

    func refreshSettings() {
        numberRowEnabled = SharedStore.shared.numberRowEnabled
        aiSuggestionsEnabled = SharedStore.shared.aiSuggestionsEnabled
        bridgeActive = SharedStore.shared.bridgeActive
        recording = SharedStore.shared.voiceRecording
        clipboardEntries = SharedStore.shared.clipboardEntries
    }

    func pressCharacter(_ value: String) {
        let output = isShifted ? value.uppercased(with: Locale(identifier: "de_DE")) : value
        insertText(output)
        playClick()
        if isShifted {
            isShifted = false
        }
    }

    func pressSpace() {
        insertText(" ")
        playClick()
    }

    func pressReturn() {
        insertText("\n")
        playClick()
        isShifted = true
    }

    func pressDelete() {
        deleteBackward()
        playClick()
    }

    func togglePage() {
        page = page == .letters ? .symbols : .letters
        isShifted = false
        playClick()
    }

    func toggleShift() {
        isShifted.toggle()
        playClick()
    }

    func toggleClipboard() {
        showClipboard.toggle()
        clipboardEntries = SharedStore.shared.clipboardEntries
        playClick()
    }

    func captureSystemPasteboard() {
        guard let text = currentPasteboardText(), !text.isEmpty else {
            flash("Zwischenablage ist leer")
            return
        }
        SharedStore.shared.addClipboardText(text)
        clipboardEntries = SharedStore.shared.clipboardEntries
        flash("Gespeichert")
    }

    func insertClipboard(_ entry: ClipboardEntry) {
        insertText(entry.text)
        playClick()
    }

    func togglePin(_ entry: ClipboardEntry) {
        SharedStore.shared.togglePin(id: entry.id)
        clipboardEntries = SharedStore.shared.clipboardEntries
    }

    func microphoneTapped() {
        refreshSettings()
        guard bridgeActive else {
            flash("Voice Bridge zuerst in der App einschalten")
            return
        }
        SharedStore.shared.sendVoiceToggle()
        recording.toggle()
        playClick()
    }

    func requestAISuggestions() {
        guard aiSuggestionsEnabled else {
            flash("KI-Vorschläge sind in der App deaktiviert")
            return
        }

        let key = SharedStore.shared.apiKey
        guard !key.isEmpty else {
            flash("OpenAI API-Key fehlt")
            return
        }

        let context = contextBeforeInput().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !context.isEmpty else {
            flash("Erst etwas schreiben")
            return
        }

        isLoadingAI = true
        Task {
            do {
                let values = try await OpenAIClient.shared.suggestions(
                    context: String(context.suffix(1200)),
                    apiKey: key,
                    model: SharedStore.shared.textModel
                )
                await MainActor.run {
                    self.suggestions = values
                    self.isLoadingAI = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingAI = false
                    self.flash("KI-Fehler")
                }
            }
        }
    }

    func flash(_ message: String) {
        statusMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard self?.statusMessage == message else { return }
            self?.statusMessage = nil
        }
    }
}

final class KeyboardViewController: UIInputViewController, UIInputViewAudioFeedback {
    private let model = KeyboardControllerModel()
    private var host: UIHostingController<KeyboardRootView>?
    private var pollTimer: Timer?
    private var lastTranscriptNonce = SharedStore.shared.transcriptNonce
    private var heightConstraint: NSLayoutConstraint?

    var enableInputClicksWhenVisible: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()

        hasDictationKey = true
        view.backgroundColor = .systemGray5

        model.insertText = { [weak self] text in
            self?.textDocumentProxy.insertText(text)
        }
        model.deleteBackward = { [weak self] in
            self?.textDocumentProxy.deleteBackward()
        }
        model.nextKeyboard = { [weak self] in
            self?.advanceToNextInputMode()
        }
        model.contextBeforeInput = { [weak self] in
            self?.textDocumentProxy.documentContextBeforeInput ?? ""
        }
        model.currentPasteboardText = {
            UIPasteboard.general.string
        }
        model.playClick = {
            UIDevice.current.playInputClick()
        }

        installKeyboardView()
        startPolling()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.needsGlobeKey = needsInputModeSwitchKey
        model.refreshSettings()
        updateHeight()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        pollTimer?.invalidate()
        pollTimer = nil
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateAutomaticShift()
        model.refreshSettings()
    }

    private func installKeyboardView() {
        let root = KeyboardRootView(model: model)
        let hosting = UIHostingController(rootView: root)
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hosting.didMove(toParent: self)
        host = hosting

        heightConstraint = view.heightAnchor.constraint(equalToConstant: 320)
        heightConstraint?.priority = .defaultHigh
        heightConstraint?.isActive = true
        updateHeight()
    }

    private func updateHeight() {
        let target: CGFloat = SharedStore.shared.numberRowEnabled ? 354 : 316
        heightConstraint?.constant = target
    }

    private func startPolling() {
        pollTimer?.invalidate()
        lastTranscriptNonce = SharedStore.shared.transcriptNonce
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.28, repeats: true) { [weak self] _ in
            self?.pollSharedState()
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
    }

    private func pollSharedState() {
        let store = SharedStore.shared
        model.bridgeActive = store.bridgeActive
        model.recording = store.voiceRecording

        if model.numberRowEnabled != store.numberRowEnabled {
            model.numberRowEnabled = store.numberRowEnabled
            updateHeight()
        }
        model.aiSuggestionsEnabled = store.aiSuggestionsEnabled

        let nonce = store.transcriptNonce
        guard !nonce.isEmpty, nonce != lastTranscriptNonce else { return }
        lastTranscriptNonce = nonce

        let text = store.lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let needsLeadingSpace = !before.isEmpty && before.last?.isWhitespace == false
        textDocumentProxy.insertText((needsLeadingSpace ? " " : "") + text)
        store.addClipboardText(text)
        model.clipboardEntries = store.clipboardEntries
        model.flash("Diktat eingefügt")
        UIDevice.current.playInputClick()
    }

    private func updateAutomaticShift() {
        guard model.page == .letters else { return }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        if before.isEmpty {
            model.isShifted = true
            return
        }

        let trimmed = before.trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = trimmed.last, ".!?".contains(last) {
            model.isShifted = true
        }
    }
}

struct KeyboardRootView: View {
    @ObservedObject var model: KeyboardControllerModel

    private let letterRows = [
        ["q","w","e","r","t","z","u","i","o","p","ü"],
        ["a","s","d","f","g","h","j","k","l","ö","ä"],
        ["y","x","c","v","b","n","m"]
    ]

    private let symbolRows = [
        ["1","2","3","4","5","6","7","8","9","0"],
        ["-","/",":",";","(",")","€","&","@","\""],
        [".",",","?","!","'","#","%","+","="]
    ]

    var body: some View {
        VStack(spacing: 5) {
            toolbar

            if model.showClipboard {
                clipboardStrip
            }

            if model.page == .letters && model.numberRowEnabled {
                numberRow
            }

            if model.page == .letters {
                letters
            } else {
                symbols
            }

            bottomRow
        }
        .padding(.horizontal, 5)
        .padding(.top, 5)
        .padding(.bottom, 7)
        .background(Color(uiColor: .systemGray5))
        .animation(.easeInOut(duration: 0.16), value: model.showClipboard)
        .animation(.easeInOut(duration: 0.16), value: model.isShifted)
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            toolbarButton(systemName: model.showClipboard ? "keyboard" : "doc.on.clipboard") {
                model.toggleClipboard()
            }

            if let status = model.statusMessage {
                Text(status)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            } else if !model.suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.suggestions, id: \.self) { suggestion in
                            Button {
                                model.insertText(suggestion + " ")
                            } label: {
                                Text(suggestion)
                                    .font(.callout)
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .frame(height: 34)
                                    .background(.thinMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                Text(model.bridgeActive ? "OpenAI Voice bereit" : "Geile Tastatur")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            toolbarButton(systemName: model.isLoadingAI ? "hourglass" : "sparkles") {
                model.requestAISuggestions()
            }

            Button {
                model.microphoneTapped()
            } label: {
                Image(systemName: model.recording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 38, height: 34)
                    .background(
                        model.recording
                            ? Color.red.opacity(0.88)
                            : (model.bridgeActive ? Color.green.opacity(0.20) : Color(uiColor: .secondarySystemFill)),
                        in: Capsule()
                    )
                    .foregroundStyle(model.recording ? Color.white : Color.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.recording ? "Diktat stoppen" : "OpenAI Diktat starten")
        }
        .frame(height: 36)
    }

    private var clipboardStrip: some View {
        VStack(spacing: 5) {
            HStack {
                Button {
                    model.captureSystemPasteboard()
                } label: {
                    Label("Aktuelle Ablage übernehmen", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)

                Spacer()

                Text("\(model.clipboardEntries.count)/100")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if model.clipboardEntries.isEmpty {
                Text("Noch keine gespeicherten Texte")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 46)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(model.clipboardEntries.prefix(12)) { entry in
                            Button {
                                model.insertClipboard(entry)
                            } label: {
                                HStack(spacing: 5) {
                                    if entry.isPinned {
                                        Image(systemName: "pin.fill")
                                            .font(.caption2)
                                    }
                                    Text(entry.text)
                                        .lineLimit(1)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 38)
                                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(entry.isPinned ? "Nicht mehr anheften" : "Anheften") {
                                    model.togglePin(entry)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(height: 72)
    }

    private var numberRow: some View {
        HStack(spacing: 5) {
            ForEach(["1","2","3","4","5","6","7","8","9","0"], id: \.self) { value in
                KeyCap(title: value, style: .normal) {
                    model.insertText(value)
                    model.playClick()
                }
            }
        }
        .frame(height: 34)
    }

    private var letters: some View {
        VStack(spacing: 7) {
            keyRow(letterRows[0])
                .padding(.horizontal, 0)

            keyRow(letterRows[1])
                .padding(.horizontal, 14)

            HStack(spacing: 6) {
                KeyCap(systemName: "shift.fill", style: model.isShifted ? .activeModifier : .modifier) {
                    model.toggleShift()
                }
                .frame(width: 44)

                keyRow(letterRows[2])

                KeyCap(systemName: "delete.left.fill", style: .modifier) {
                    model.pressDelete()
                }
                .frame(width: 44)
            }
        }
    }

    private var symbols: some View {
        VStack(spacing: 7) {
            keyRow(symbolRows[0])
            keyRow(symbolRows[1])
                .padding(.horizontal, 8)
            keyRow(symbolRows[2])
                .padding(.horizontal, 24)
        }
    }

    private func keyRow(_ values: [String]) -> some View {
        HStack(spacing: 5) {
            ForEach(values, id: \.self) { value in
                KeyCap(title: model.page == .letters && model.isShifted ? value.uppercased(with: Locale(identifier: "de_DE")) : value, style: .normal) {
                    model.pressCharacter(value)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var bottomRow: some View {
        HStack(spacing: 6) {
            KeyCap(title: model.page == .letters ? "123" : "ABC", style: .modifier) {
                model.togglePage()
            }
            .frame(width: 50)

            if model.needsGlobeKey {
                KeyCap(systemName: "globe", style: .modifier) {
                    model.nextKeyboard()
                    model.playClick()
                }
                .frame(width: 44)
            }

            KeyCap(title: "Leerzeichen", style: .normal, font: .system(size: 15)) {
                model.pressSpace()
            }
            .frame(maxWidth: .infinity)

            KeyCap(title: "return", style: .modifier, font: .system(size: 13)) {
                model.pressReturn()
            }
            .frame(width: 72)
        }
        .frame(height: 46)
    }

    private func toolbarButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 34)
                .background(Color(uiColor: .secondarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

private struct KeyCap: View {
    enum Style {
        case normal
        case modifier
        case activeModifier
    }

    let title: String?
    let systemName: String?
    let style: Style
    let font: Font
    let action: () -> Void

    init(
        title: String,
        style: Style,
        font: Font = .system(size: 20),
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemName = nil
        self.style = style
        self.font = font
        self.action = action
    }

    init(
        systemName: String,
        style: Style,
        font: Font = .system(size: 18, weight: .medium),
        action: @escaping () -> Void
    ) {
        self.title = nil
        self.systemName = systemName
        self.style = style
        self.font = font
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let title {
                    Text(title)
                        .font(font)
                } else if let systemName {
                    Image(systemName: systemName)
                        .font(font)
                }
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(AppleKeyButtonStyle(style: style))
        .frame(height: 44)
    }
}

private struct AppleKeyButtonStyle: ButtonStyle {
    let style: KeyCap.Style

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(background(configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 5.5, style: .continuous))
            .shadow(color: .black.opacity(configuration.isPressed ? 0.06 : 0.20), radius: 0.5, x: 0, y: 1)
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(.easeOut(duration: 0.07), value: configuration.isPressed)
    }

    private func background(_ pressed: Bool) -> Color {
        if pressed {
            return Color(uiColor: .systemGray3)
        }

        switch style {
        case .normal:
            return Color(uiColor: .systemBackground)
        case .modifier:
            return Color(uiColor: .systemGray3)
        case .activeModifier:
            return Color(uiColor: .systemBackground)
        }
    }
}
