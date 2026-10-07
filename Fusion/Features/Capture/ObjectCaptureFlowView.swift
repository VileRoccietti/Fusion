import RealityKit
import SwiftUI

/// Full-screen guided photogrammetry capture flow
struct ObjectCaptureFlowView: View {
    @Environment(ScanStorage.self) private var storage
    @Environment(\.dismiss) private var dismiss

    @State private var engine: ObjectCaptureEngine?
    @State private var finishedRecord: ScanRecord?
    @State private var startupError: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let engine {
                content(for: engine)
            } else if let startupError {
                FailureOverlay(message: startupError) { dismiss() }
            } else {
                ProgressView("Inicializando sensores...")
                    .tint(.white)
            }
        }
        .preferredColorScheme(.dark)
        .task { startIfNeeded() }
        .onDisappear {
            if finishedRecord == nil { engine?.cancel() }
        }
    }

    @ViewBuilder
    private func content(for engine: ObjectCaptureEngine) -> some View {
        switch engine.phase {
        case .idle, .preparing, .readyToDetect, .framing, .capturing:
            captureStage(engine: engine)

        case .reconstructing(let progress):
            ReconstructionOverlay(progress: progress)

        case .done(let record):
            CaptureResultView(record: record, poseAdvice: engine.poseAdvice) { dismiss() }
                .task { finishedRecord = record }

        case .failed(let message):
            FailureOverlay(message: message) { dismiss() }

        case .cancelled:
            Color.clear.task { dismiss() }
        }
    }

    private func captureStage(engine: ObjectCaptureEngine) -> some View {
        ZStack {
            if let session = engine.session {
                ObjectCaptureView(session: session)
                    .ignoresSafeArea()
            } else {
                ProgressView("Calibrando LiDAR...")
                    .tint(.white)
            }

            CaptureOverlay(engine: engine, onCancel: {
                engine.cancel()
                dismiss()
            })
        }
    }

    private func startIfNeeded() {
        guard engine == nil else { return }
        let engine = ObjectCaptureEngine(storage: storage)
        do {
            try engine.start()
            self.engine = engine
        } catch {
            startupError = error.localizedDescription
        }
    }
}

// MARK: - Capture Overlay

private struct CaptureOverlay: View {
    let engine: ObjectCaptureEngine
    let onCancel: () -> Void

    @State private var isFinishing = false
    @State private var finishError: String?
    @State private var isConfirmingCancel = false
    @State private var isConfirmingFinish = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            hintStack
            actionBar
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .confirmationDialog(
            "¿Cancelar el escaneo?",
            isPresented: $isConfirmingCancel,
            titleVisibility: .visible
        ) {
            Button("Cancelar y Salir", role: .destructive, action: onCancel)
            Button("Continuar Escaneando", role: .cancel) {}
        } message: {
            Text(engine.shotCount > 0 ? "Se descartarán \(engine.shotCount) imágenes capturadas." : "No se han capturado fotos aún.")
        }
        .confirmationDialog(
            "Base del objeto sin escanear",
            isPresented: $isConfirmingFinish,
            titleVisibility: .visible
        ) {
            Button("Generar Modelo Igualmente") { finish() }
            Button("Voltear Objeto", role: .cancel) {}
        } message: {
            Text("Solo se completó una órbita. Si deseas capturar la base inferior, voltea el objeto antes de finalizar.")
        }
        .alert(
            "Error al generar modelo",
            isPresented: Binding(get: { finishError != nil }, set: { if !$0 { finishError = nil } })
        ) {
            Button("OK") { finishError = nil }
        } message: {
            Text(finishError ?? "")
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                isConfirmingCancel = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.5), in: Circle())
            }
            .tint(.white)

            Spacer()

            if case .capturing(let shots, let limit) = engine.phase {
                ShotCounter(shots: shots, limit: limit, passes: engine.completedPasses)
            }
        }
        .padding(.top, 4)
    }

    private var hintStack: some View {
        VStack(spacing: 6) {
            if let warning = engine.trackingWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.orange.opacity(0.9), in: Capsule())
            }

            ForEach(engine.hints, id: \.self) { hint in
                Text(hint)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.65), in: Capsule())
            }
        }
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var actionBar: some View {
        VStack(spacing: 12) {
            switch engine.phase {
            case .idle, .preparing:
                Label("Inicializando sensores...", systemImage: "circle.dotted")
                    .font(.subheadline.weight(.semibold))

            case .readyToDetect:
                Label("Apunta la cámara hacia el objeto", systemImage: "viewfinder")
                    .font(.subheadline.weight(.semibold))
                if let hint = engine.detectionHint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                Button("Iniciar Detección") { engine.attemptDetection() }
                    .buttonStyle(PrimaryCapsuleStyle())

            case .framing:
                Label("Ajusta el objeto dentro de la caja 3D", systemImage: "cube")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 10) {
                    Button("Reiniciar Caja") { engine.resetDetection() }
                        .buttonStyle(SecondaryCapsuleStyle())
                    Button("Comenzar Escaneo") { engine.beginCapture() }
                        .buttonStyle(PrimaryCapsuleStyle())
                }

            case .capturing where engine.canFinishCurrentPass:
                Label("¡Órbita 360° Completada!", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)

                Text(engine.isObjectFlippable
                     ? "Puedes voltear el objeto para capturar la base inferior o añadir otra altura."
                     : "Puedes realizar una nueva órbita a diferente altura para enriquecer el modelo.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    if engine.isObjectFlippable {
                        Button("Voltear y Continuar") { engine.beginPassAfterFlip() }
                            .buttonStyle(SecondaryCapsuleStyle())
                    }
                    Button("Añadir Otra Altura") { engine.beginAdditionalPass() }
                        .buttonStyle(SecondaryCapsuleStyle())
                }

                Button {
                    if engine.completedPasses == 0 {
                        isConfirmingFinish = true
                    } else {
                        finish()
                    }
                } label: {
                    if isFinishing {
                        ProgressView().tint(.black)
                    } else {
                        Text("Finalizar y Reconstruir Modelo 3D")
                    }
                }
                .buttonStyle(PrimaryCapsuleStyle())
                .disabled(isFinishing)

            case .capturing:
                Label("Muévete lentamente alrededor del objeto", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.subheadline.weight(.semibold))

            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 22))
        .sensoryFeedback(.success, trigger: engine.canFinishCurrentPass) { _, new in new }
    }

    private func finish() {
        isFinishing = true
        Task {
            do {
                _ = try await engine.finish()
            } catch is CancellationError {
            } catch {
                finishError = error.localizedDescription
            }
            isFinishing = false
        }
    }
}

// MARK: - Shot Counter

private struct ShotCounter: View {
    let shots: Int
    let limit: Int
    let passes: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "camera.fill")
                .font(.caption)
                .foregroundStyle(.yellow)
            Text("\(shots) fotos")
                .font(.footnote.weight(.semibold).monospacedDigit())
            if passes > 0 {
                Text("· Pase \(passes + 1)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.black.opacity(0.5), in: Capsule())
    }
}

// MARK: - Reconstruction Overlay

private struct ReconstructionOverlay: View {
    let progress: ReconstructionProgress

    var body: some View {
        VStack(spacing: 26) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.15), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: max(progress.fraction, 0.001))
                    .stroke(Color.yellow, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(progress.fraction * 100))%")
                    .font(.title2.weight(.bold).monospacedDigit())
            }
            .frame(width: 120, height: 120)

            VStack(spacing: 8) {
                Text(progress.stage?.displayName ?? "Reconstruyendo modelo 3D...")
                    .font(.headline)

                if let remaining = progress.remainingText {
                    Text("Tiempo restante: \(remaining)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text("Mantén la app abierta mientras se procesa la geometría.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .padding()
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

// MARK: - Capture Result View

private struct CaptureResultView: View {
    let record: ScanRecord
    let poseAdvice: [String]
    let onDone: () -> Void

    @Environment(ScanStorage.self) private var storage

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ModelPreviewView(url: storage.modelURL(for: record))
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(spacing: 6) {
                    Label("¡Escaneo 3D Completado!", systemImage: "checkmark.circle.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.green)

                    if let count = record.imageCount {
                        Text("\(count) fotos procesadas con éxito")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(poseAdvice, id: \.self) { note in
                    Label(note, systemImage: "lightbulb.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .multilineTextAlignment(.leading)
                        .padding(10)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }

                Button("Abrir en Estudio 3D", action: onDone)
                    .buttonStyle(PrimaryCapsuleStyle())
                    .padding(.horizontal, 20)
            }
            .padding()
        }
        .sensoryFeedback(.success, trigger: record.id)
    }
}

private struct FailureOverlay: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .font(.subheadline)
            Button("Cerrar", action: onDismiss)
                .buttonStyle(PrimaryCapsuleStyle())
                .padding(.horizontal, 40)
        }
        .padding(32)
        .sensoryFeedback(.error, trigger: message)
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

private struct SecondaryCapsuleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(.white.opacity(configuration.isPressed ? 0.28 : 0.16), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 1))
    }
}
