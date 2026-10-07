@preconcurrency import ARKit
import RealityKit
import SwiftUI

/// Tactical military LiDAR night vision view for navigating and measuring in total darkness
struct LiDARNightVisionView: View {
    @Binding var currentMode: CameraHubMode
    @State private var engine = LiDARNightVisionEngine()
    @Environment(\.dismiss) private var dismiss

    init(currentMode: Binding<CameraHubMode>? = nil) {
        self._currentMode = currentMode ?? .constant(.nightVision)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // AR LiDAR Mesh Viewport
            ARNightVisionContainer(engine: engine)
                .ignoresSafeArea()

            // Optical NVG Tube Vignette & Phosphor Glow
            nightVisionTubeOverlay
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Tactical Military HUD
            VStack {
                hudTopBar
                Spacer()
                hudCenterReticle
                Spacer()
                hudBottomControls
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            engine.start()
        }
        .onDisappear {
            engine.stop()
        }
    }

    // MARK: - Tactical HUD Overlays

    private var hudTopBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(engine.mode.tintColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: engine.mode.tintColor, radius: 4)

                    Text(engine.mode.militaryCode)
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(engine.mode.tintColor)
                }

                Text(String(format: "HDG: %03.0f° N | GAIN: %.1fx", engine.compassHeading, engine.gainMultiplier))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(engine.mode.tintColor.opacity(0.8))
            }

            Spacer()

            Button {
                engine.toggleTorch()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: engine.isIRIlluminatorOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    Text(engine.isIRIlluminatorOn ? "IR ON" : "IR OFF")
                }
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(engine.isIRIlluminatorOn ? engine.mode.tintColor : Color.black.opacity(0.6), in: Capsule())
                .foregroundStyle(engine.isIRIlluminatorOn ? Color.black : engine.mode.tintColor)
                .overlay(
                    Capsule().stroke(engine.mode.tintColor.opacity(0.4), lineWidth: 1)
                )
            }
        }
        .padding(.top, 40)
    }

    private var hudCenterReticle: some View {
        VStack(spacing: 6) {
            ZStack {
                // Crosshairs
                Path { path in
                    path.move(to: CGPoint(x: -30, y: 0))
                    path.addLine(to: CGPoint(x: -8, y: 0))
                    path.move(to: CGPoint(x: 8, y: 0))
                    path.addLine(to: CGPoint(x: 30, y: 0))

                    path.move(to: CGPoint(x: 0, y: -30))
                    path.addLine(to: CGPoint(x: 0, y: -8))
                    path.move(to: CGPoint(x: 0, y: 8))
                    path.addLine(to: CGPoint(x: 0, y: 30))
                }
                .stroke(engine.mode.tintColor, lineWidth: 1.5)
                .frame(width: 60, height: 60)

                Circle()
                    .stroke(engine.mode.tintColor.opacity(0.6), lineWidth: 1)
                    .frame(width: 44, height: 44)

                Circle()
                    .fill(engine.mode.tintColor)
                    .frame(width: 4, height: 4)
            }

            // Laser Rangefinder Metric Readout
            HStack(spacing: 4) {
                Image(systemName: "laser.burst")
                    .font(.system(size: 10))
                Text("DISTANCIA: [ \(engine.targetDistanceText) ]")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
            }
            .foregroundStyle(engine.proximityWarning ? Color.red : engine.mode.tintColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke((engine.proximityWarning ? Color.red : engine.mode.tintColor).opacity(0.5), lineWidth: 1)
            )

            if engine.proximityWarning {
                Text("⚠️ ADVERTENCIA: OBSTÁCULO CERCANO")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.8), in: Capsule())
            }
        }
    }

    private var hudBottomControls: some View {
        VStack(spacing: 12) {
            // Phosphor mode selector
            HStack(spacing: 8) {
                ForEach(NightVisionMode.allCases) { mode in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            engine.mode = mode
                        }
                        HapticFeedback.selection()
                    } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                engine.mode == mode ? engine.mode.tintColor : Color.black.opacity(0.6),
                                in: Capsule()
                            )
                            .foregroundStyle(engine.mode == mode ? Color.black : Color.white)
                            .overlay(
                                Capsule().stroke(engine.mode.tintColor.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
            }

            // Mode Selector Row (FOTO | VIDEO | NOCTURNO)
            CameraModeSelectorRow(currentMode: $currentMode)

            // Snapshot capture button
            Button {
                HapticFeedback.heavy()
            } label: {
                ZStack {
                    Circle()
                        .stroke(engine.mode.tintColor, lineWidth: 3)
                        .frame(width: 68, height: 68)

                    Circle()
                        .fill(engine.mode.tintColor)
                        .frame(width: 54, height: 54)

                    Image(systemName: "camera.viewfinder")
                        .font(.title3)
                        .foregroundStyle(Color.black)
                }
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - Vignette Tube Overlay

    private var nightVisionTubeOverlay: some View {
        ZStack {
            // Circular NVG Tube Bezel
            RadialGradient(
                gradient: Gradient(colors: [
                    engine.mode.tintColor.opacity(0.08),
                    engine.mode.tintColor.opacity(0.25),
                    Color.black.opacity(0.85),
                    Color.black
                ]),
                center: .center,
                startRadius: 160,
                endRadius: 420
            )
            .blendMode(.screen)

            // Tactical scanline overlay
            VStack(spacing: 3) {
                ForEach(0..<80) { _ in
                    Rectangle()
                        .fill(Color.white.opacity(0.015))
                        .frame(height: 1)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - AR Viewport Container

private struct ARNightVisionContainer: UIViewRepresentable {
    let engine: LiDARNightVisionEngine

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.session = engine.arSession

        // Render LiDAR scene mesh overlay
        arView.environment.sceneUnderstanding.options = [.occlusion, .physics]
        arView.debugOptions.insert(.showSceneUnderstanding)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
