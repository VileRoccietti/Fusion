import SwiftUI
import CoreMotion

/// Gyroscopic artificial horizon and roll/pitch level indicator with tactile feedback
@MainActor
final class HorizonLevelGuide: ObservableObject {
    @Published var rollDegrees: Double = 0
    @Published var pitchDegrees: Double = 0
    @Published var isLevel: Bool = false

    private let motionManager = CMMotionManager()
    private var didVibrateForLevel = false

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }

            let roll = motion.attitude.roll * 180.0 / .pi
            let pitch = motion.attitude.pitch * 180.0 / .pi

            self.rollDegrees = roll
            self.pitchDegrees = pitch

            let leveled = abs(roll) < 0.6 && abs(pitch) < 3.0

            if leveled && !self.isLevel {
                HapticFeedback.levelSnapped()
            }
            self.isLevel = leveled
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }
}

/// SwiftUI Overlay rendering the aviation-style horizon guide
struct HorizonLevelOverlay: View {
    @ObservedObject var guide: HorizonLevelGuide

    var body: some View {
        ZStack {
            // Center reticle
            Circle()
                .stroke(guide.isLevel ? Color.green : Color.white.opacity(0.35), lineWidth: 1.5)
                .frame(width: 24, height: 24)

            // Dynamic rolling line
            Rectangle()
                .fill(guide.isLevel ? Color.green : Color.white.opacity(0.75))
                .frame(width: 80, height: 2)
                .rotationEffect(.degrees(guide.rollDegrees))
                .animation(.easeOut(duration: 0.1), value: guide.rollDegrees)

            // Degree readout
            if !guide.isLevel && abs(guide.rollDegrees) > 1.0 {
                Text(String(format: "%.1f°", guide.rollDegrees))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .offset(y: 22)
            }
        }
        .allowsHitTesting(false)
    }
}
