import SwiftUI
import RealityKit
import ARKit

/// Full Augmented Reality workspace for real-world inspection, 1:1 metric scale testing,
/// and interactive AR Ruler measurements.
struct ARStudioView: View {
    let modelURL: URL
    @Environment(\.dismiss) private var dismiss

    @StateObject private var rulerTool = ARRulerTool()
    @State private var isRulerActive = false
    @State private var isMetricLocked = true
    @State private var modelPlaced = false
    @State private var trackingStateText = "Buscando superficies..."
    @State private var currentARView: ARView?

    var body: some View {
        ZStack {
            ARViewContainer(
                modelURL: modelURL,
                rulerTool: rulerTool,
                isRulerActive: $isRulerActive,
                isMetricLocked: $isMetricLocked,
                modelPlaced: $modelPlaced,
                trackingStateText: $trackingStateText,
                onViewCreated: { view in
                    self.currentARView = view
                }
            )
            .ignoresSafeArea()

            // Overlays
            VStack {
                topBar
                Spacer()
                if isRulerActive {
                    rulerHUD
                }
                bottomControls
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.6), in: Circle())
            }

            Spacer()

            Text(trackingStateText)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.6), in: Capsule())
                .foregroundStyle(.white)

            Spacer()

            Button {
                isRulerActive.toggle()
                HapticFeedback.selection()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "ruler.fill")
                    Text("Regla AR")
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isRulerActive ? Color.yellow : Color.black.opacity(0.6), in: Capsule())
                .foregroundStyle(isRulerActive ? Color.black : Color.white)
            }
        }
        .padding()
    }

    // MARK: - Ruler HUD

    private var rulerHUD: some View {
        VStack(spacing: 8) {
            if rulerTool.activeStartPoint != nil {
                Text("Toca el segundo punto para medir la distancia.")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.7), in: Capsule())
            } else {
                Text("Toca cualquier punto del objeto o la habitación.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.7), in: Capsule())
            }

            if !rulerTool.measurements.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(rulerTool.measurements.enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 6) {
                                Text("#\(index + 1):")
                                    .fontWeight(.bold)
                                Text("\(item.centimetersFormatted) (\(item.millimeters) mm)")
                            }
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.yellow.opacity(0.5), lineWidth: 1))
                            .foregroundStyle(.white)
                        }

                        Button {
                            if let arView = currentARView {
                                rulerTool.clearMeasurements(in: arView)
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .padding(8)
                                .background(.red.opacity(0.8), in: Circle())
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(spacing: 12) {
            Button {
                isMetricLocked.toggle()
                HapticFeedback.light()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isMetricLocked ? "lock.fill" : "lock.open.fill")
                    Text(isMetricLocked ? "Escala 1:1 Fija" : "Escala Libre")
                }
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(isMetricLocked ? Color.green : Color.white)
            }

            Spacer()

            Text(modelPlaced ? "Arrastra para mover / rota" : "Toca el plano para colocar")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding()
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
        .padding()
    }
}

// MARK: - ARView Container

private struct ARViewContainer: UIViewRepresentable {
    let modelURL: URL
    @ObservedObject var rulerTool: ARRulerTool
    @Binding var isRulerActive: Bool
    @Binding var isMetricLocked: Bool
    @Binding var modelPlaced: Bool
    @Binding var trackingStateText: String
    var onViewCreated: (ARView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        context.coordinator.arView = arView

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }

        arView.session.run(config)
        arView.session.delegate = context.coordinator

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)

        onViewCreated(arView)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.parent = self
    }

    @MainActor
    final class Coordinator: NSObject, ARSessionDelegate {
        var parent: ARViewContainer
        weak var arView: ARView?
        var modelEntity: Entity?
        var modelAnchor: AnchorEntity?

        init(_ parent: ARViewContainer) {
            self.parent = parent
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView else { return }
            let location = gesture.location(in: arView)

            if parent.isRulerActive {
                // Raycast for ruler point
                let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any)
                if let hit = results.first {
                    let point = SIMD3<Float>(hit.worldTransform.columns.3.x, hit.worldTransform.columns.3.y, hit.worldTransform.columns.3.z)
                    parent.rulerTool.addPoint(point, in: arView)
                }
            } else {
                // Place or reposition model
                if let hit = arView.raycast(from: location, allowing: .existingPlaneGeometry, alignment: .horizontal).first ??
                    arView.raycast(from: location, allowing: .estimatedPlane, alignment: .horizontal).first {
                    placeModel(at: hit.worldTransform)
                }
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
                    if let collisionEntity = entity as? HasCollision {
                        arView.installGestures([.rotation, .translation], for: collisionEntity)
                    }

                    let anchor = AnchorEntity(world: transform)
                    anchor.addChild(entity)
                    arView.scene.addAnchor(anchor)

                    self.modelAnchor = anchor
                    self.modelEntity = entity
                    self.parent.modelPlaced = true
                    HapticFeedback.success()
                } catch {
                    print("Error loading AR model: \(error)")
                }
            }
        }

        nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            let text: String
            switch camera.trackingState {
            case .normal:
                text = "Listo: Superficie lista"
            case .notAvailable:
                text = "Seguimiento no disponible"
            case .limited(let reason):
                switch reason {
                case .initializing:
                    text = "Iniciando LiDAR..."
                case .relocalizing:
                    text = "Relocalizando..."
                case .excessiveMotion:
                    text = "Movimiento rápido"
                case .insufficientFeatures:
                    text = "Apunta a una superficie con textura"
                @unknown default:
                    text = "Seguimiento limitado"
                }
            }
            Task { @MainActor in
                self.parent.trackingStateText = text
            }
        }
    }
}
