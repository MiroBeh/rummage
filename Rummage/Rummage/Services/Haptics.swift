import UIKit

/// A tap when a decision registers, so you can keep your eyes on the photo.
/// Off is off: the settings toggle is the only thing that governs this.
enum Haptics {
    static let settingsKey = "rummage.haptics"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: settingsKey) as? Bool ?? true
    }

    static func tap(for decision: SwipeDecision) {
        guard isEnabled else { return }
        let style: UIImpactFeedbackGenerator.FeedbackStyle = decision == .delete ? .medium : .light
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    /// A light tap when holding the card opens the full photo.
    static func peek() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
