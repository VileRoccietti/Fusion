import AVFoundation
import SwiftUI

/// Capture flow for turntable photogrammetry (tripod + rotating subject)
struct TurntableFlowView: View {
    @Environment(ScanStorage.self) private var storage
    @Environment(\.dismiss) private var dismiss

    @State private var engine: TurntableCaptureEngine?
    @State private var finishedRecord: ScanRecord?
    @State private var startupError: String?
    @State private var hasSeenSetupTips = false

    @State private var maskFrame = CGRect(x: 80, y: 240, width: 220, height: 260)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let engine {
                content(for: engine)
            } else if let startupError {
                MessageOverlay(
                    title: "No se pudo iniciar la cámara",
                    message: startupError,
                    systemImage: "exclamationmark.triangle.fill"
                ) { dismiss() }
            } else {
                ProgressView("Preparando sensor...").tint(.white)
            }
        }
        .preferredColorScheme(.dark)
        .task { startIfNeeded() }
        .onDisappear {
            if finishedRecord == nil { engine?.cancel() }
        }
    }

    @ViewBuilder
    private func content(for engine: TurntableCaptureEngine) -> some View {
        switch engine.phase {
        case .idle, .preparing:
            ProgressView("Inicializando cámara...").tint(.white)

        case .readyToDetect, .framing, .capturing:
            if hasSeenSetupTips {
                captureStage(engine: engine)
            } else {
                TurntableSetupGuide(deliversDepth: engine.deliversDepth) {
                    hasSeenSetupTips = true
                } onCancel: {
                    engine.cancel()
                    dismiss()
                }
            }

        case .reconstructing(let progress):
            ReconstructionOverlay(progress: progress)

        case .done(let record):
            TurntableResultView(record: record, warnings: engine.warnings) { dismiss() }
                .task { finishedRecord = record }

        case .failed(let message):
            MessageOverlay(
                title: "Escaneo no completado",
                message: message,
                systemImage: "exclamationmark.triangle.fill"
            ) { dismiss() }

        case .cancelled:
            Color.clear.task { dismiss() }
        }
    }

    private func captureStage(engine: TurntableCaptureEngine) -> some View {
        ZStack {
            if let session = engine.session {
                TurntableCameraPreview(session: session, maskFrame: maskFrame) { normalized in
                    engine.objectMaskRect = normalized
                }
                .ignoresSafeArea()
            }

            // Interactive mask rect
            ObjectMaskRectangle(frame: $maskFrame)

            TurntableOverlay(engine: engine) {
                engine.cancel()
                dismiss()
            }
        }
    }

    private func startIfNeeded() {
        guard engine == nil else { return }
        let engine = TurntableCaptureEngine(storage: storage)
        do {
            try engine.start()
            self.engine = engine
        } catch {
            startupError = error.localizedDescription
        }
    }
}

// MARK: - Setup Guide

private struct TurntableSetupGuide: View {
    let deliversDepth: Bool
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "rotate.3d")
                .font(.system(size: 60))
                .foregroundStyle(.yellow)

            Text("Modo Mesa Giratoria")
                .font(.title2.weight(.bold))

            VStack(alignment: .leading, spacing: 14) {
                Label("Fija tu iPhone en un trípode apuntando al objeto.", systemImage: "iphone")
                Label("Usa un fondo liso y gira el objeto lentamente a mano o con plato giratorio.", systemImage: "arrow.trianglehead.clockwise")
                Label("La app fija el enfoque y descarta automáticamente fotos movidas.", systemImage: "camera.filters")
                if deliversDepth {
                    Label("Sensor LiDAR activo: inyecta escala milimétrica en cada foto.", systemImage: "ruler")
                        .foregroundStyle(.green)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 24)

            Spacer()

            Button("Entendido, Continuar") {
                onContinue()
                HapticFeedback.medium()
            }
            .buttonStyle(PrimaryCapsuleStyle())
            .padding(.horizontal, 30)

            Button("Cancelar", action: onCancel)
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
        .padding()
    }
}

// MARK: - Mask Rectangle

private struct ObjectMaskRectangle: View {
    @Binding var frame: CGRect

    var body: some View {
        ZStack {
            Rectangle()
                .stroke(Color.yellow, lineWidth: 2)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            frame.origin = CGPoint(
                                x: frame.origin.x + value.translation.width,
                                y: frame.origin.y + value.translation.height
                            )
                        }
                )

            Text("Área de Enmascarado")
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.yellow, in: Capsule())
                .foregroundStyle(.black)
                .position(x: frame.midX, y: frame.minY - 12)
        }
    }
}

// MARK: - Overlay

private struct TurntableOverlay: View {
    let engine: TurntableCaptureEngine
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

                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .foregroundStyle(.yellow)
                    Text("\(engine.shotCount) fotos")
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
                if let reason = engine.lastRejectionReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.7), in: Capsule())
                }

                HStack(spacing: 14) {
                    Button {
                        engine.toggleAutoCapture()
                        HapticFeedback.medium()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: engine.isAutoCapturing ? "pause.fill" : "play.fill")
                            Text(engine.isAutoCapturing ? "Pausar Auto" : "Captura Auto")
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                    }

                    Button {
                        engine.captureNow()
                        HapticFeedback.light()
                    } label: {
                        ZStack {
                            Circle().stroke(Color.white, lineWidth: 2).frame(width: 56, height: 56)
                            Circle().fill(Color.white).frame(width: 46, height: 46)
                        }
                    }

                    if engine.canFinish {
                        Button {
                            finish()
                        } label: {
                            Text("Generar")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.yellow, in: Capsule())
                        }
                    }
                }
            }
            .padding()
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
            .padding()
        }
    }

    private func finish() {
        isFinishing = true
        Task {
            do {
                _ = try await engine.finish()
            } catch {}
            isFinishing = false
        }
    }
}

// MARK: - Preview Wrapper

private struct TurntableCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let maskFrame: CGRect
    let onCoordinateChange: (CGRect) -> Void

    func makeUIView(context: Context) -> PreviewContainer {
        let view = PreviewContainer()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewContainer, context: Context) {
        let layer = uiView.videoPreviewLayer
        let normalized = layer.metadataOutputRectConverted(fromLayerRect: maskFrame)
        onCoordinateChange(normalized)
    }

    final class PreviewContainer: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

private struct TurntableResultView: View {
    let record: ScanRecord
    let warnings: [String]
    let onDone: () -> Void
    @Environment(ScanStorage.self) private var storage

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModelPreviewView(url: storage.modelURL(for: record))
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                Label("Modelo 3D Generado", systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.green)

                Button("Abrir en Estudio 3D", action: onDone)
                    .buttonStyle(PrimaryCapsuleStyle())
                    .padding(.horizontal, 30)
            }
            .padding()
        }
    }
}

private struct MessageOverlay: View {
    let title: String
    let message: String
    let systemImage: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage).font(.largeTitle).foregroundStyle(.orange)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Cerrar", action: onDismiss).buttonStyle(PrimaryCapsuleStyle()).padding(.horizontal, 40)
        }
        .padding(32)
    }
}

private struct ReconstructionOverlay: View {
    let progress: ReconstructionProgress

    var body: some View {
        VStack(spacing: 20) {
            ProgressView(value: progress.fraction)
                .tint(.yellow)
            Text(progress.stage?.displayName ?? "Procesando fotogrametría...")
                .font(.headline)
        }
        .padding(30)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding()
    }
}

private struct PrimaryCapsuleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.yellow.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
    }
}
