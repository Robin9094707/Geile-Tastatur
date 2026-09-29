import UIKit

enum HapticEngine {
    private static let selection = UISelectionFeedbackGenerator()
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let notification = UINotificationFeedbackGenerator()

    static func prepare() {
        guard SharedStore.shared.hapticsEnabled else { return }
        selection.prepare()
        soft.prepare()
        light.prepare()
        medium.prepare()
        notification.prepare()
    }

    static func key() {
        guard SharedStore.shared.hapticsEnabled else { return }
        selection.selectionChanged()
        selection.prepare()
    }

    static func softTap() {
        guard SharedStore.shared.hapticsEnabled else { return }
        soft.impactOccurred(intensity: 0.55)
        soft.prepare()
    }

    static func action() {
        guard SharedStore.shared.hapticsEnabled else { return }
        light.impactOccurred(intensity: 0.72)
        light.prepare()
    }

    static func strong() {
        guard SharedStore.shared.hapticsEnabled else { return }
        medium.impactOccurred(intensity: 0.82)
        medium.prepare()
    }

    static func success() {
        guard SharedStore.shared.hapticsEnabled else { return }
        notification.notificationOccurred(.success)
        notification.prepare()
    }

    static func warning() {
        guard SharedStore.shared.hapticsEnabled else { return }
        notification.notificationOccurred(.warning)
        notification.prepare()
    }

    static func error() {
        guard SharedStore.shared.hapticsEnabled else { return }
        notification.notificationOccurred(.error)
        notification.prepare()
    }
}
