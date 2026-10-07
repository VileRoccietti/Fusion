import UIKit

/// Centralized tactile haptics engine for camera controls, scanning events, and 3D interactions.
@MainActor
enum HapticFeedback {
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    static func prepare() {
        lightGenerator.prepare()
        selectionGenerator.prepare()
    }

    /// Discrete tick for rotating wheels, sliders, and stepper increments
    static func selection() {
        selectionGenerator.selectionChanged()
    }

    /// Light click for minor buttons and segment switches
    static func light() {
        lightGenerator.impactOccurred()
    }

    /// Medium feedback for shutter button, mode changes, and 3D tool selections
    static func medium() {
        mediumGenerator.impactOccurred()
    }

    /// Heavy feedback for scan completion, level snapping, and cutting planes
    static func heavy() {
        heavyGenerator.impactOccurred()
    }

    /// Success notification vibration
    static func success() {
        notificationGenerator.notificationOccurred(.success)
    }

    /// Warning vibration (e.g. tracking lost, moving too fast)
    static func warning() {
        notificationGenerator.notificationOccurred(.warning)
    }

    /// Error notification vibration
    static func error() {
        notificationGenerator.notificationOccurred(.error)
    }

    /// Snaps into level when artificial horizon aligns to 0 degrees
    static func levelSnapped() {
        mediumGenerator.impactOccurred(intensity: 0.8)
    }
}
