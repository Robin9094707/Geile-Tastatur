import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var voiceBridge: VoiceBridgeManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .environmentObject(voiceBridge)
                .tabItem { Label("Start", systemImage: "keyboard") }
                .tag(0)

            ClipboardManagerView()
                .tabItem { Label("Ablage", systemImage: "doc.on.clipboard") }
                .tag(1)

            SettingsView()
                .tabItem { Label("Einstellungen", systemImage: "slider.horizontal.3") }
                .tag(2)
        }
        .tint(.primary)
    }
}

private struct HomeView: View {
    @EnvironmentObject private var voiceBridge: VoiceBridgeManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    hero

                    GlassSection(title: "1. Tastatur aktivieren", icon: "keyboard.badge.ellipsis") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Einstellungen → Allgemein → Tastatur → Tastaturen → Tastatur hinzufügen → Geile Tastatur")
                                .font(.callout)
                            Text("Für OpenAI, Zwischenablage und gemeinsame Einstellungen muss „Vollen Zugriff erlauben“ aktiviert sein.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    GlassSection(title: "2. OpenAI Voice Bridge", icon: "waveform.badge.mic") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(voiceBridge.isBridgeActive ? Color.green : Color.secondary.opacity(0.4))
                                    .frame(width: 10, height: 10)
                                Text(voiceBridge.statusText)
                                    .font(.subheadline.weight(.semibold))
                            }

                            Text("Apple erlaubt einer Drittanbieter-Tastatur keinen direkten Mikrofonzugriff. Die Voice Bridge lässt deshalb diese App die Aufnahme übernehmen, während die Tastatur Start/Stop steuert.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("Hinweis: Solange die Bridge aktiv ist, bleibt die Mikrofon-Audiosession offen. iOS zeigt deshalb den orangefarbenen Mikrofonindikator. Schalte die Bridge aus, wenn du sie nicht brauchst.")
                                .font(.caption)
                                .foregroundStyle(.orange)

                            Button {
                                voiceBridge.isBridgeActive ? voiceBridge.stopBridge() : voiceBridge.startBridge()
                            } label: {
                                Label(
                                    voiceBridge.isBridgeActive ? "Voice Bridge ausschalten" : "Voice Bridge einschalten",
                                    systemImage: voiceBridge.isBridgeActive ? "stop.circle.fill" : "mic.circle.fill"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .adaptiveGlassButton(prominent: !voiceBridge.isBridgeActive)

                            if let error = voiceBridge.lastError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    GlassSection(title: "So diktierst du", icon: "sparkles") {
                        VStack(alignment: .leading, spacing: 8) {
                            step("Voice Bridge einschalten.")
                            step("In einer anderen App „Geile Tastatur“ auswählen.")
                            step("Oben rechts auf das Mikrofon tippen und sprechen.")
                            step("Noch einmal tippen: OpenAI transkribiert, bereinigt Selbstkorrekturen und die Tastatur fügt den fertigen Text ein.")
                        }
                    }
                }
                .padding(18)
            }
            .navigationTitle("Geile Tastatur")
            .background(background)
        }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 54, weight: .medium))
                .symbolRenderingMode(.hierarchical)
            Text("Tippen wie iOS. Diktieren mit KI.")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("QWERTZ · Clipboard · Pins · Zahlenreihe · OpenAI Spracheingabe · optionale KI-Vorschläge")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .adaptiveGlass(cornerRadius: 28)
    }

    private func step(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
                .font(.callout)
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct ClipboardManagerView: View {
    @State private var entries: [ClipboardEntry] = SharedStore.shared.clipboardEntries
    @State private var newText = ""
    @State private var pendingDelete: ClipboardEntry?
    @State private var showClearConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Textbaustein hinzufügen …", text: $newText, axis: .vertical)
                        .lineLimit(2...5)

                    Button {
                        SharedStore.shared.addClipboardText(newText, pinned: true)
                        newText = ""
                        reload()
                    } label: {
                        Label("Als festen Text speichern", systemImage: "pin.fill")
                    }
                }

                if entries.isEmpty {
                    ContentUnavailableView(
                        "Noch nichts gespeichert",
                        systemImage: "doc.on.clipboard",
                        description: Text("Füge Textbausteine hier oder über die Tastatur hinzu.")
                    )
                } else {
                    Section("Verlauf") {
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack(alignment: .top) {
                                    Text(entry.text)
                                        .lineLimit(4)
                                        .textSelection(.enabled)
                                    Spacer()
                                    if entry.isPinned {
                                        Image(systemName: "pin.fill")
                                            .foregroundStyle(.orange)
                                    }
                                }

                                Text(entry.createdAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    SharedStore.shared.togglePin(id: entry.id)
                                    reload()
                                } label: {
                                    Label(entry.isPinned ? "Lösen" : "Pinnen", systemImage: "pin")
                                }
                                .tint(.orange)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    pendingDelete = entry
                                } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Zwischenablage")
            .toolbar {
                if !entries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Aufräumen") {
                            showClearConfirmation = true
                        }
                    }
                }
            }
            .confirmationDialog(
                "Eintrag wirklich löschen?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Löschen", role: .destructive) {
                    if let pendingDelete {
                        SharedStore.shared.deleteClipboard(id: pendingDelete.id)
                    }
                    pendingDelete = nil
                    reload()
                }
                Button("Abbrechen", role: .cancel) { pendingDelete = nil }
            }
            .confirmationDialog(
                "Nicht angehefteten Verlauf löschen?",
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Verlauf löschen", role: .destructive) {
                    SharedStore.shared.clearUnpinnedClipboard()
                    reload()
                }
                Button("Abbrechen", role: .cancel) {}
            }
            .onAppear(perform: reload)
        }
    }

    private func reload() {
        entries = SharedStore.shared.clipboardEntries
    }
}

private struct SettingsView: View {
    @State private var apiKey = SharedStore.shared.apiKey
    @State private var numberRow = SharedStore.shared.numberRowEnabled
    @State private var aiSuggestions = SharedStore.shared.aiSuggestionsEnabled
    @State private var cleanupTranscript = SharedStore.shared.cleanupTranscriptEnabled
    @State private var keySaved = false

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenAI") {
                    SecureField("sk-…", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        SharedStore.shared.apiKey = apiKey
                        keySaved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            keySaved = false
                        }
                    } label: {
                        Label(keySaved ? "Gespeichert" : "API-Key speichern", systemImage: keySaved ? "checkmark.circle.fill" : "key.fill")
                    }

                    Text("Der Schlüssel wird nur im gemeinsamen lokalen App-Group-Speicher von App und Tastatur abgelegt und niemals ins GitHub-Repository geschrieben.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Tastatur") {
                    Toggle("Zahlenreihe dauerhaft anzeigen", isOn: $numberRow)
                        .onChange(of: numberRow) { _, value in
                            SharedStore.shared.numberRowEnabled = value
                        }

                    Toggle("KI-Schreibvorschläge", isOn: $aiSuggestions)
                        .onChange(of: aiSuggestions) { _, value in
                            SharedStore.shared.aiSuggestionsEnabled = value
                        }

                    Text("KI-Vorschläge sind standardmäßig aus und werden nur auf Knopfdruck angefragt. Dafür wird der Textkontext an OpenAI gesendet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Spracheingabe") {
                    Toggle("Diktat intelligent bereinigen", isOn: $cleanupTranscript)
                        .onChange(of: cleanupTranscript) { _, value in
                            SharedStore.shared.cleanupTranscriptEnabled = value
                        }

                    LabeledContent("Transkription", value: SharedStore.shared.transcriptionModel)
                    LabeledContent("Text-Korrektur", value: SharedStore.shared.textModel)

                    Text("Die Standardmodelle sind gpt-transcribe für Sprache und gpt-6-luna für optionale Textbereinigung/Vorschläge.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Datenschutz") {
                    Text("Ohne vollen Tastaturzugriff funktionieren normales Tippen und lokale Funktionen. Netzwerkfunktionen, App-Group-Synchronisierung und OpenAI benötigen den erweiterten Zugriff.")
                    Text("Die Voice Bridge zeichnet nur zwischen Start und Stop als Datei auf. Die Audiosession selbst bleibt bei aktivierter Bridge aus technischen iOS-Gründen geöffnet.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Einstellungen")
        }
    }
}

private struct GlassSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .adaptiveGlass(cornerRadius: 24)
    }
}

private extension View {
    @ViewBuilder
    func adaptiveGlass(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    func adaptiveGlassButton(prominent: Bool) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }
}
