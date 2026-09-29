import SwiftUI

@main
struct GeileTastaturApp: App {
    @StateObject private var voiceBridge = VoiceBridgeManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(voiceBridge)
        }
    }
}
