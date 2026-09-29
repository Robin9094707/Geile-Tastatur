import AVFoundation
import Combine
import Foundation

final class VoiceBridgeManager: ObservableObject {
    @Published private(set) var isBridgeActive = SharedStore.shared.bridgeActive
    @Published private(set) var isRecording = SharedStore.shared.voiceRecording
    @Published private(set) var statusText = "Bereit"
    @Published private(set) var lastError: String?

    private let engine = AVAudioEngine()
    private let fileLock = NSLock()
    private let commandQueue = DispatchQueue(label: "GeileTastatur.VoiceBridge.CommandQueue")
    private var commandTimer: DispatchSourceTimer?
    private var lastCommandNonce = SharedStore.shared.voiceCommandNonce
    private var recordingFile: AVAudioFile?
    private var recordingURL: URL?
    private var captureEnabled = false
    private var tapInstalled = false

    deinit {
        commandTimer?.cancel()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
        }
    }

    func startBridge() {
        lastError = nil
        let session = AVAudioSession.sharedInstance()
        session.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                if granted {
                    self.activateBridge()
                } else {
                    self.lastError = "Mikrofonzugriff wurde nicht erlaubt."
                    self.statusText = "Mikrofonfreigabe fehlt"
                }
            }
        }
    }

    func stopBridge() {
        if SharedStore.shared.voiceRecording {
            cancelCapture()
        }

        commandTimer?.cancel()
        commandTimer = nil

        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        SharedStore.shared.bridgeActive = false
        SharedStore.shared.voiceRecording = false
        isBridgeActive = false
        isRecording = false
        statusText = "Voice Bridge aus"
    }

    private func activateBridge() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.allowBluetooth])
            try session.setActive(true)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)

            if tapInstalled {
                input.removeTap(onBus: 0)
                tapInstalled = false
            }

            input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                self?.handleAudioBuffer(buffer)
            }
            tapInstalled = true

            engine.prepare()
            try engine.start()

            SharedStore.shared.bridgeActive = true
            SharedStore.shared.voiceRecording = false
            isBridgeActive = true
            isRecording = false
            statusText = "Voice Bridge aktiv – Mikrofon wartet auf Tastatur"
            lastCommandNonce = SharedStore.shared.voiceCommandNonce
            startCommandPolling()
        } catch {
            lastError = error.localizedDescription
            statusText = "Voice Bridge konnte nicht starten"
            SharedStore.shared.bridgeActive = false
            isBridgeActive = false
        }
    }

    private func startCommandPolling() {
        commandTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: commandQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(160), leeway: .milliseconds(40))
        timer.setEventHandler { [weak self] in
            self?.pollForKeyboardCommand()
        }
        timer.resume()
        commandTimer = timer
    }

    private func pollForKeyboardCommand() {
        let store = SharedStore.shared
        let nonce = store.voiceCommandNonce
        guard !nonce.isEmpty, nonce != lastCommandNonce else { return }
        lastCommandNonce = nonce

        switch store.voiceCommand {
        case "toggle":
            if store.voiceRecording {
                finishCapture()
            } else {
                beginCapture()
            }
        case "cancel":
            cancelCapture()
        default:
            break
        }
    }

    private func beginCapture() {
        guard isBridgeActive || SharedStore.shared.bridgeActive else { return }

        let format = engine.inputNode.outputFormat(forBus: 0)
        let baseURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedStore.appGroupID
        ) ?? FileManager.default.temporaryDirectory
        let url = baseURL.appendingPathComponent("dictation-\(UUID().uuidString).wav")

        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)

            fileLock.lock()
            recordingFile = file
            recordingURL = url
            captureEnabled = true
            fileLock.unlock()

            SharedStore.shared.voiceRecording = true
            DispatchQueue.main.async { [weak self] in
                self?.isRecording = true
                self?.statusText = "Sprich jetzt …"
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.lastError = error.localizedDescription
                self?.statusText = "Aufnahme konnte nicht gestartet werden"
            }
        }
    }

    private func finishCapture() {
        fileLock.lock()
        captureEnabled = false
        let url = recordingURL
        recordingFile = nil
        recordingURL = nil
        fileLock.unlock()

        SharedStore.shared.voiceRecording = false
        DispatchQueue.main.async { [weak self] in
            self?.isRecording = false
            self?.statusText = "Transkription läuft …"
        }

        guard let url else { return }

        Task { [weak self] in
            do {
                let store = SharedStore.shared
                let key = store.apiKey
                var text = try await OpenAIClient.shared.transcribe(
                    fileURL: url,
                    apiKey: key,
                    model: store.transcriptionModel
                )

                if store.cleanupTranscriptEnabled {
                    text = try await OpenAIClient.shared.cleanTranscript(
                        text,
                        apiKey: key,
                        model: store.textModel
                    )
                }

                store.publishTranscript(text)
                try? FileManager.default.removeItem(at: url)

                await MainActor.run {
                    self?.statusText = "Fertig – Text wurde an die Tastatur übergeben"
                    self?.lastError = nil
                }
            } catch {
                try? FileManager.default.removeItem(at: url)
                await MainActor.run {
                    self?.lastError = error.localizedDescription
                    self?.statusText = "Transkription fehlgeschlagen"
                }
            }
        }
    }

    private func cancelCapture() {
        fileLock.lock()
        captureEnabled = false
        let url = recordingURL
        recordingFile = nil
        recordingURL = nil
        fileLock.unlock()

        if let url {
            try? FileManager.default.removeItem(at: url)
        }

        SharedStore.shared.voiceRecording = false
        DispatchQueue.main.async { [weak self] in
            self?.isRecording = false
            self?.statusText = self?.isBridgeActive == true
                ? "Voice Bridge aktiv – Aufnahme verworfen"
                : "Voice Bridge aus"
        }
    }

    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        fileLock.lock()
        defer { fileLock.unlock() }
        guard captureEnabled, let recordingFile else { return }
        try? recordingFile.write(from: buffer)
    }
}
