import RoomPlan
import SwiftUI

/// Full-screen capture flow for RoomPlan LiDAR room scanning
struct RoomFlowView: View {
    @Environment(ScanStorage.self) private var storage
    @Environment(\.dismiss) private var dismiss

    @State private var engine: RoomCaptureEngine?
    @State private var finishedRecord: ScanRecord?
    @State private var startupError: String?
    @State private var hasSeenGuide = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let engine {
                content(for: engine)
            } else if let startupError {
                RoomFailureView(message: startupError) { dismiss() }
            } else {
                ProgressView("Iniciando RoomPlan...").tint(.white)
            }
        }
        .preferredColorScheme(.dark)
        .task { startIfNeeded() }
        .onDisappear {
            if finishedRecord == nil { engine?.cancel() }
        }
    }

    @ViewBuilder
    private func content(for engine: RoomCaptureEngine) -> some View {
        switch engine.phase {
        case .idle, .preparing, .readyToDetect, .framing, .capturing:
            if hasSeenGuide {
                captureStage(engine: engine)
            } else {
                RoomGuideView {
                    hasSeenGuide = true
                    engine.beginCapture()
                } onCancel: {
                    engine.cancel()
                    dismiss()
                }
            }

        case .reconstructing(let progress):
            VStack(spacing: 16) {
                ProgressView(value: progress.fraction)
                    .tint(.yellow)
                    .frame(maxWidth: 240)
                Text(progress.stage?.displayName ?? "Procesando estructura de la habitación...")
                    .font(.headline)
            }
            .padding(32)

        case .done(let record):
            RoomResultView(record: record, summary: engine.summary) { dismiss() }
                .task { finishedRecord = record }

        case .failed(let message):
            RoomFailureView(message: message) { dismiss() }

        case .cancelled:
            Color.clear.task { dismiss() }
        }
    }

    private func captureStage(engine: RoomCaptureEngine) -> some View {
        ZStack {
            RoomCaptureContainer(captureView: engine.captureView)
                .ignoresSafeArea()

            RoomOverlay(engine: engine) {
                engine.cancel()
                dismiss()
            }
        }
    }

    private func startIfNeeded() {
        guard engine == nil else { return }
        let engine = RoomCaptureEngine(storage: storage)
        do {
            try engine.start()
            self.engine = engine
        } catch {
            startupError = error.localizedDescription
        }
    }
}

// MARK: - Guide View

private struct RoomGuideView: View {
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "door.left.hand.open")
                .font(.system(size: 60))
                .foregroundStyle(.yellow)

            Text("Escaneo LiDAR de Habitaciones")
                .font(.title2.weight(.bold))

            VStack(alignment: .leading, spacing: 14) {
                Label("Camina lentamente por la habitación apuntando a esquinas y paredes.", systemImage: "figure.walk")
                Label("El LiDAR clasifica automáticamente puertas, ventanas y muebles.", systemImage: "cube.box")
                Label("Las paredes lisas se miden con absoluta precisión milimétrica.", systemImage: "ruler")
            }
            .font(.subheadline)
            .padding(.horizontal, 24)

            Spacer()

            Button("Comenzar Escaneo") {
                onStart()
                HapticFeedback.medium()
            }
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.yellow, in: Capsule())
            .padding(.horizontal, 30)

            Button("Cancelar", action: onCancel)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

// MARK: - Overlay

private struct RoomOverlay: View {
    let engine: RoomCaptureEngine
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

                Picker("Estilo", selection: Binding(get: { engine.exportStyle }, set: { engine.exportStyle = $0 })) {
                    ForEach(RoomExportStyle.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Spacer()

            Button {
                isFinishing = true
                Task {
                    _ = try? await engine.finish()
                    isFinishing = false
                }
            } label: {
                HStack(spacing: 8) {
                    if isFinishing {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Finalizar y Guardar Habitación")
                    }
                }
                .font(.headline)
                .foregroundStyle(.black)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(Color.yellow, in: Capsule())
            }
            .disabled(isFinishing)
            .padding(.bottom, 20)
        }
    }
}

private struct RoomCaptureContainer: UIViewRepresentable {
    let captureView: RoomCaptureView

    func makeUIView(context: Context) -> RoomCaptureView {
        captureView
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}

private struct RoomResultView: View {
    let record: ScanRecord
    let summary: RoomSummary?
    let onDone: () -> Void
    @Environment(ScanStorage.self) private var storage

    var body: some View {
        VStack(spacing: 20) {
            ModelPreviewView(url: storage.modelURL(for: record))
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            Label("Habitación 3D Guardada", systemImage: "checkmark.circle.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(.green)

            if let summary {
                Text(summary.text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button("Abrir en Estudio 3D", action: onDone)
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

private struct RoomFailureView: View {
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
