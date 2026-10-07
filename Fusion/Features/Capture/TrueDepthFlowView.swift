import ARKit
import SceneKit
import SwiftUI
import simd

/// Full-screen capture flow for TrueDepth front IR structured-light point cloud scanner
struct TrueDepthFlowView: View {
    @Environment(ScanStorage.self) private var storage
    @Environment(\.dismiss) private var dismiss

    @State private var engine: TrueDepthEngine?
    @State private var finishedRecord: ScanRecord?
    @State private var startupError: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let engine {
                content(for: engine)
            } else if let startupError {
                DepthFailureView(message: startupError) { dismiss() }
            } else {
                ProgressView("Iniciando TrueDepth...").tint(.white)
            }
        }
        .preferredColorScheme(.dark)
        .task { startIfNeeded() }
        .onDisappear {
            if finishedRecord == nil { engine?.cancel() }
        }
    }

    @ViewBuilder
    private func content(for engine: TrueDepthEngine) -> some View {
        switch engine.phase {
        case .idle, .preparing, .readyToDetect, .framing, .capturing:
            captureStage(engine: engine)

        case .reconstructing(let progress):
            VStack(spacing: 16) {
                ProgressView(value: progress.fraction)
                    .progressViewStyle(.linear)
                    .tint(.yellow)
                    .frame(maxWidth: 240)
                Text(progress.stage?.displayName ?? "Guardando nube de puntos...")
                    .font(.headline)
            }
            .padding(32)

        case .done(let record):
            DepthResultView(record: record) { dismiss() }
                .task { finishedRecord = record }

        case .failed(let message):
            DepthFailureView(message: message) { dismiss() }

        case .cancelled:
            Color.clear.task { dismiss() }
        }
    }

    private func captureStage(engine: TrueDepthEngine) -> some View {
        ZStack {
            if let session = engine.session {
                DepthSceneView(
                    session: session,
                    points: engine.snapshot.renderPoints,
                    aimPoint: engine.snapshot.aimPoint,
                    regionCenter: engine.snapshot.regionCenter,
                    regionHalfExtent: engine.snapshot.regionHalfExtent
                )
                .ignoresSafeArea()

                CentreReticle()
            } else {
                ProgressView("Calibrando sensor frontal...").tint(.white)
            }

            DepthCaptureOverlay(engine: engine) {
                engine.cancel()
                dismiss()
            }
        }
    }

    private func startIfNeeded() {
        guard engine == nil else { return }
        let engine = TrueDepthEngine(storage: storage)
        do {
            try engine.start()
            self.engine = engine
        } catch {
            startupError = error.localizedDescription
        }
    }
}

// MARK: - Centre Reticle

private struct CentreReticle: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.35), lineWidth: 1.5)
                .frame(width: 44, height: 44)
            Circle()
                .fill(Color.white.opacity(0.7))
                .frame(width: 4, height: 4)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Depth Capture Overlay

private struct DepthCaptureOverlay: View {
    let engine: TrueDepthEngine
    let onCancel: () -> Void

    @State private var isFinishing = false

    var body: some View {
        VStack {
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(.black.opacity(0.5), in: Circle())
                }
                .tint(.white)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "sensor.tag.radiowaves.forward.fill")
                        .foregroundStyle(.yellow)
                    Text("\(engine.snapshot.pointCount.formatted()) pts")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.5), in: Capsule())
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Spacer()

            VStack(spacing: 12) {
                if let warning = engine.trackingWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(.orange.opacity(0.85), in: Capsule())
                }

                if let advice = engine.distanceAdvice {
                    Text(advice.text)
                        .font(.caption)
                        .foregroundStyle(advice.isGood ? .green : .yellow)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.65), in: Capsule())
                }

                HStack(spacing: 12) {
                    Button {
                        if engine.snapshot.regionCenter != nil {
                            engine.clearRegion()
                        } else {
                            engine.lockRegion()
                        }
                        HapticFeedback.selection()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: engine.snapshot.regionCenter != nil ? "crop" : "viewfinder")
                            Text(engine.snapshot.regionCenter != nil ? "Liberar Región" : "Fijar Región")
                        }
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .foregroundStyle(.white)
                    }

                    Button {
                        isFinishing = true
                        Task {
                            _ = try? await engine.finish()
                            isFinishing = false
                        }
                    } label: {
                        Text("Guardar Nube PLY")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Color.yellow, in: Capsule())
                    }
                    .disabled(engine.snapshot.pointCount == 0 || isFinishing)
                }
            }
            .padding()
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
            .padding()
        }
    }
}

// MARK: - SceneKit Point Cloud Viewer

private struct DepthSceneView: UIViewRepresentable {
    let session: ARSession
    let points: [SIMD3<Float>]
    let aimPoint: SIMD3<Float>?
    let regionCenter: SIMD3<Float>?
    let regionHalfExtent: Float

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 60
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        let cloudNodeName = "PointCloudNode"
        uiView.scene.rootNode.childNode(withName: cloudNodeName, recursively: false)?.removeFromParentNode()

        guard !points.isEmpty else { return }

        let vertices = points.map { SCNVector3($0.x, $0.y, $0.z) }
        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: (0..<UInt32(points.count)).map { $0 }, primitiveType: .point)
        element.pointSize = 3
        element.minimumPointScreenSpaceRadius = 1.0
        element.maximumPointScreenSpaceRadius = 4.0

        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.firstMaterial?.lightingModel = .constant
        geometry.firstMaterial?.diffuse.contents = UIColor.systemGreen

        let node = SCNNode(geometry: geometry)
        node.name = cloudNodeName
        uiView.scene.rootNode.addChildNode(node)
    }
}

private struct DepthResultView: View {
    let record: ScanRecord
    let onDone: () -> Void
    @Environment(ScanStorage.self) private var storage

    var body: some View {
        VStack(spacing: 20) {
            PointCloudPreviewView(url: storage.modelURL(for: record))
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            Label("Nube de Puntos PLY Generada", systemImage: "checkmark.circle.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(.green)

            if let pts = record.pointCount {
                Text("\(pts.formatted()) puntos métricos guardados")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button("Abrir en Biblioteca", action: onDone)
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.yellow, in: Capsule())
                .padding(.horizontal, 40)
        }
        .padding()
    }
}

private struct DepthFailureView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(.orange)
            Text(message).font(.subheadline).multilineTextAlignment(.center)
            Button("Cerrar", action: onDismiss)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 30)
                .padding(.vertical, 10)
                .background(Color.yellow, in: Capsule())
        }
        .padding(32)
    }
}
