import Foundation
import Observation
import RealityKit
import SwiftUI
import os

/// Guided photogrammetry engine utilizing RealityKit and LiDAR
@MainActor
@Observable
final class ObjectCaptureEngine: ScanEngine {
    private static let logger = Logger(subsystem: "com.vileroccietti.Fusion", category: "objectcapture")

    static let kind: ScanEngineKind = .objectCapture

    static var availability: EngineAvailability {
        guard DeviceCapabilities.supportsObjectCapture else {
            return .unsupportedDevice(reason: "Object Capture no es compatible con este dispositivo. Se requiere un iPhone con LiDAR.")
        }
        guard DeviceCapabilities.supportsPhotogrammetry else {
            return .unsupportedDevice(reason: "Este dispositivo no soporta fotogrametría en el dispositivo.")
        }
        return .available
    }

    // MARK: - Observable State

    private(set) var phase: ScanPhase = .idle
    private(set) var session: ObjectCaptureSession?
    private(set) var hints: [String] = []
    private(set) var trackingWarning: String?
    private(set) var detectionHint: String?
    private(set) var isObjectFlippable = true
    private(set) var canFinishCurrentPass = false
    private(set) var completedPasses = 0
    private(set) var shotCount = 0
    private(set) var poseAdvice: [String] = []

    // MARK: - Private

    private let storage: ScanStorage
    private let reconstructor = PhotogrammetryReconstructor()
    private var workspace: ScanWorkspace?
    private var observers: [Task<Void, Never>] = []
    private var detectionRetry: Task<Void, Never>?
    private var passTransition: Task<Void, Never>?
    private var completionWaiter: CheckedContinuation<Void, Error>?

    init(storage: ScanStorage) {
        self.storage = storage
    }

    // MARK: - Lifecycle

    func start() throws {
        guard case .available = Self.availability else {
            throw ScanEngineError.sessionUnavailable(Self.availability.blockedReason ?? "Dispositivo no compatible")
        }

        phase = .preparing

        let workspace: ScanWorkspace
        do {
            workspace = try storage.makeWorkspace()
        } catch {
            phase = .failed(message: error.localizedDescription)
            throw ScanEngineError.sessionUnavailable(error.localizedDescription)
        }
        self.workspace = workspace

        let session = ObjectCaptureSession()
        self.session = session
        observe(session)

        var configuration = ObjectCaptureSession.Configuration()
        configuration.checkpointDirectory = workspace.checkpointURL
        configuration.isOverCaptureEnabled = true

        session.start(imagesDirectory: workspace.imagesURL, configuration: configuration)
        session.shouldPlayHaptics = true
    }

    func finish() async throws -> ScanRecord {
        guard let session, let workspace else {
            throw ScanEngineError.sessionUnavailable("No hay sesión activa.")
        }

        let detail = ReconstructionDetail.reduced

        if session.state != .completed {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                completionWaiter = continuation
                session.finish()
            }
        }

        let capturedShots = shotCount
        phase = .reconstructing(ReconstructionProgress())

        let output: PhotogrammetryReconstructor.Output
        do {
            output = try await reconstructor.reconstruct(workspace: workspace, detail: detail) { [weak self] progress in
                self?.phase = .reconstructing(progress)
            }
        } catch {
            phase = .failed(message: error.localizedDescription)
            throw error
        }

        if let poses = output.poses {
            poseAdvice = poses.advice
        }

        let record = ScanRecord(
            id: workspace.id,
            name: Self.defaultName(for: Date()),
            engine: Self.kind,
            isMetricallyScaled: true,
            imageCount: capturedShots,
            detail: detail,
            summary: output.poses?.summaryText
        )
        storage.commit(record, workspace: workspace)

        teardownObservers()
        self.session = nil
        phase = .done(record)
        return record
    }

    func cancel() {
        teardownObservers()
        completionWaiter?.resume(throwing: ScanEngineError.cancelled)
        completionWaiter = nil
        session?.cancel()
        session = nil
        if let workspace {
            storage.discard(workspace)
            self.workspace = nil
        }
        phase = .cancelled
    }

    // MARK: - Capture Flow Controls

    func attemptDetection(retriesRemaining: Int = 8) {
        guard let session, session.state == .ready else { return }

        if session.startDetecting() {
            detectionHint = nil
            return
        }

        guard retriesRemaining > 0 else {
            detectionHint = "La detección no inició. Apunta al objeto e inténtalo de nuevo."
            return
        }

        detectionHint = session.cameraTracking.warning ?? "Apunta el dispositivo al objeto"
        detectionRetry?.cancel()
        detectionRetry = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.attemptDetection(retriesRemaining: retriesRemaining - 1)
        }
    }

    func beginCapture() {
        session?.startCapturing()
    }

    func resetDetection() {
        session?.resetDetection()
    }

    func beginAdditionalPass() {
        beginPass(flipped: false)
    }

    func beginPassAfterFlip() {
        beginPass(flipped: true)
    }

    private func beginPass(flipped: Bool) {
        guard let session, session.state == .capturing else { return }

        passTransition?.cancel()
        passTransition = Task { [weak self] in
            if !session.isPaused { session.pause() }

            var pausedConfirmed = session.isPaused
            for _ in 0..<20 where !pausedConfirmed {
                try? await Task.sleep(for: .milliseconds(50))
                if Task.isCancelled { return }
                pausedConfirmed = session.isPaused
            }

            guard let self, !Task.isCancelled else { return }

            guard pausedConfirmed else {
                self.detectionHint = "No se pudo pausar la sesión. Finaliza para generar el modelo."
                return
            }

            if flipped {
                session.beginNewScanPassAfterFlip()
            } else {
                session.beginNewScanPass()
            }
            session.resume()

            self.completedPasses += 1
            self.canFinishCurrentPass = false
        }
    }

    // MARK: - Observation

    private func observe(_ session: ObjectCaptureSession) {
        observers = [
            Task { [weak self] in
                for await state in session.stateUpdates {
                    guard let self else { return }
                    self.handle(state: state, session: session)
                }
            },
            Task { [weak self] in
                for await feedback in session.feedbackUpdates {
                    guard let self else { return }
                    self.hints = feedback.compactMap(\.hint)
                    if feedback.contains(.objectNotFlippable) {
                        self.isObjectFlippable = false
                    }
                }
            },
            Task { [weak self] in
                for await shots in session.numberOfShotsTakenUpdates {
                    guard let self else { return }
                    self.shotCount = shots
                    if case .capturing = self.phase {
                        self.phase = .capturing(shots: shots, limit: session.maximumNumberOfInputImages)
                    }
                    self.trackingWarning = session.cameraTracking.warning
                }
            },
            Task { [weak self] in
                for await completed in session.userCompletedScanPassUpdates {
                    guard let self else { return }
                    self.canFinishCurrentPass = completed
                }
            },
        ]
    }

    private func handle(state: ObjectCaptureSession.CaptureState, session: ObjectCaptureSession) {
        switch state {
        case .initializing:
            phase = .preparing
        case .ready:
            phase = .readyToDetect
            attemptDetection()
        case .detecting:
            detectionRetry?.cancel()
            detectionRetry = nil
            detectionHint = nil
            phase = .framing
        case .capturing:
            phase = .capturing(shots: session.numberOfShotsTaken, limit: session.maximumNumberOfInputImages)
        case .finishing:
            break
        case .completed:
            completionWaiter?.resume()
            completionWaiter = nil
        case .failed(let error):
            completionWaiter?.resume(throwing: error)
            completionWaiter = nil
            phase = .failed(message: Self.describe(error))
        @unknown default:
            break
        }
    }

    private func teardownObservers() {
        for observer in observers { observer.cancel() }
        observers = []
        detectionRetry?.cancel()
        detectionRetry = nil
        passTransition?.cancel()
        passTransition = nil
        hints = []
        trackingWarning = nil
        detectionHint = nil
    }

    private static func describe(_ error: Error) -> String {
        guard let sessionError = error as? ObjectCaptureSession.Error else {
            return error.localizedDescription
        }
        switch sessionError {
        case .insufficientStorage(let requiredBytes):
            let needed = ByteCountFormatter.string(fromByteCount: requiredBytes, countStyle: .file)
            return "Almacenamiento insuficiente — se requieren al menos \(needed) de espacio libre."
        case .directoryNotEmpty:
            return "El directorio de trabajo no está vacío. Reinicie la aplicación."
        case .sensorFailed:
            return "La cámara o el sensor LiDAR no respondieron."
        case .trackingFailed:
            return "Se perdió el seguimiento de posición. Prueba una superficie con más textura y luz uniforme."
        case .cancelled:
            return "Escaneo cancelado."
        @unknown default:
            return error.localizedDescription
        }
    }

    private static func defaultName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "d MMM HH:mm"
        return "Escaneo \(formatter.string(from: date))"
    }
}
