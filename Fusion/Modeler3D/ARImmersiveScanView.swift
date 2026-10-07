@preconcurrency import ARKit
import RealityKit
import SwiftUI

/// Ultra-immersive AR viewer for placing and inspecting 3D scans in the real world
struct ARImmersiveScanView: View {
    let modelURL: URL
    let scanName: String

    @Environment(\.dismiss) private var dismiss
    @State private var isRulerActive = false
    @State private var modelPlaced = false
    @State private var selectedScalePreset: ScalePreset = .fullReal
    @State private var isWireframeHologram = false
    @State private var trackingPrompt: String = "Apunta al suelo o una mesa para colocar el escaneo"

    enum ScalePreset: Float, CaseIterable, Identifiable {
        case fullReal = 1.0
        case half = 0.5
        case quarter = 0.25
        case desk = 0.10

        var id: Float { rawValue }

        var label: String {
            switch self {
            case .fullReal: "1:1 Real"
            case .half: "50%"
            case .quarter: "25%"
            case .desk: "10% Escritorio"
            }
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // RealityKit AR Viewport with LiDAR Scene Understanding
            ImmersiveARRepresentable(
                modelURL: modelURL,
                isRulerActive: $isRulerActive,
                modelPlaced: $modelPlaced,
                scaleMultiplier: selectedScalePreset.rawValue,
                isWireframe: isWireframeHologram,
                trackingPrompt: $trackingPrompt
            )
            .ignoresSafeArea()

            // Cinematic In-Universe HUD
            VStack {
                topBar
                Spacer()
                if !modelPlaced {
                    placementGuidanceCard
                }
                Spacer()
                bottomToolDeck
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
                HapticFeedback.light()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(scanName)
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)

                Text(trackingPrompt)
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
            .padding(.leading, 8)

            Spacer()

            // Hologram Wireframe toggle
            Button {
                isWireframeHologram.toggle()
                HapticFeedback.selection()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isWireframeHologram ? "waveform.path.ecg" : "cube.transparent")
                    Text(isWireframeHologram ? "Holograma" : "Sólido")
                }
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isWireframeHologram ? Color.cyan : Color.black.opacity(0.6), in: Capsule())
                .foregroundStyle(isWireframeHologram ? Color.black : Color.white)
            }
        }
        .padding(.top, 40)
    }

    // MARK: - Placement Guidance Card

    private var placementGuidanceCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.tap.fill")
                .font(.title2)
                .foregroundStyle(.yellow)

            Text("Toca en cualquier superficie para proyectar en AR")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)

            Text("El escáner LiDAR del iPhone 16 Pro Max calculará la escala física exacta.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 24)
    }

    // MARK: - Bottom Tool Deck

    private var bottomToolDeck: some View {
        VStack(spacing: 12) {
            // Scale Selector Pills
            HStack(spacing: 8) {
                ForEach(ScalePreset.allCases) { preset in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            selectedScalePreset = preset
                        }
                        HapticFeedback.selection()
                    } label: {
                        Text(preset.label)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                selectedScalePreset == preset ? Color.yellow : Color.black.opacity(0.6),
                                in: Capsule()
                            )
                            .foregroundStyle(selectedScalePreset == preset ? Color.black : Color.white)
                    }
                }
            }

            // Quick Actions
            HStack(spacing: 16) {
                // Laser Ruler Toggle
                Button {
                    isRulerActive.toggle()
                    HapticFeedback.medium()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "ruler.fill")
                        Text(isRulerActive ? "Regla Activa" : "Medir AR")
                    }
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(isRulerActive ? Color.yellow : Color.white.opacity(0.15), in: Capsule())
                    .foregroundStyle(isRulerActive ? Color.black : Color.white)
                }

                // Reset Placement
                Button {
                    modelPlaced = false
                    HapticFeedback.light()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reposicionar")
                    }
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.15), in: Capsule())
                    .foregroundStyle(.white)
                }
            }
        }
        .padding(.bottom, 20)
    }
}

// MARK: - RealityKit Immersive AR Container

private struct ImmersiveARRepresentable: UIViewRepresentable {
    let modelURL: URL
    @Binding var isRulerActive: Bool
    @Binding var modelPlaced: Bool
    let scaleMultiplier: Float
    let isWireframe: Bool
    @Binding var trackingPrompt: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        context.coordinator.arView = arView

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]

        // Enable LiDAR Scene Understanding & Human Occlusion
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            config.frameSemantics.insert(.personSegmentationWithDepth)
        }

        arView.environment.sceneUnderstanding.options = [.occlusion, .physics, .collision]
        arView.session.run(config)
        arView.session.delegate = context.coordinator

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tap)

        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateScale(scaleMultiplier)
    }

    @MainActor
    final class Coordinator: NSObject, ARSessionDelegate {
        var parent: ImmersiveARRepresentable
        weak var arView: ARView?
        var modelAnchor: AnchorEntity?
        var modelEntity: Entity?

        init(_ parent: ImmersiveARRepresentable) {
            self.parent = parent
        }

        func updateScale(_ scale: Float) {
            guard let modelEntity else { return }
            let s = SIMD3<Float>(repeating: scale)
            modelEntity.scale = s
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView else { return }
            let location = gesture.location(in: arView)

            // Hit test real planes or raycast
            let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any)
            if let hit = results.first {
                placeModel(at: hit.worldTransform)
            }
        }

        private func placeModel(at transform: simd_float4x4) {
            guard let arView else { return }

            if let anchor = modelAnchor {
                anchor.transform = Transform(matrix: transform)
                HapticFeedback.light()
                return
            }

            Task { @MainActor in
                do {
                    let entity = try await Entity(contentsOf: parent.modelURL)
                    entity.generateCollisionShapes(recursive: true)
                    entity.scale = SIMD3<Float>(repeating: parent.scaleMultiplier)

                    if let collisionEntity = entity as? HasCollision {
                        arView.installGestures([.rotation, .translation], for: collisionEntity)
                    }

                    let anchor = AnchorEntity(world: transform)
                    anchor.addChild(entity)
                    arView.scene.addAnchor(anchor)

                    self.modelAnchor = anchor
                    self.modelEntity = entity
                    self.parent.modelPlaced = true
                    self.parent.trackingPrompt = "Modelo anclado con LiDAR a escala real"
                    HapticFeedback.success()
                } catch {
                    print("Error loading AR model: \(error)")
                }
            }
        }

        nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            let prompt: String
            switch camera.trackingState {
            case .normal:
                prompt = "Superficie detectada: Toca para colocar"
            case .notAvailable:
                prompt = "Seguimiento no disponible"
            case .limited(let reason):
                switch reason {
                case .initializing: prompt = "Iniciando escáner LiDAR..."
                case .relocalizing: prompt = "Relocalizando posición..."
                case .excessiveMotion: prompt = "Mueve el iPhone más despacio"
                case .insufficientFeatures: prompt = "Apunta a una superficie con textura o luz"
                @unknown default: prompt = "Modo AR activo"
                }
            }
            Task { @MainActor in
                self.parent.trackingPrompt = prompt
            }
        }
    }
}
