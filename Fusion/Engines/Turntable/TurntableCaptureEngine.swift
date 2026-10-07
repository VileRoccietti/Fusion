import AVFoundation
import Foundation
import Observation
import os

/// Photogrammetry capture engine with tripod-mounted device and rotating object
@MainActor
@Observable
final class TurntableCaptureEngine: ScanEngine {
    private static let logger = Logger(subsystem: "com.vileroccietti.Fusion", category: "turntable")

    static let kind: ScanEngineKind = .turntable

    static var availability: EngineAvailability {
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else {
            return .unsupportedDevice(reason: "No se encontró la cámara trasera principal.")
        }
        guard DeviceCapabilities.supportsPhotogrammetry else {
            return .unsupportedDevice(reason: "Este dispositivo no soporta fotogrametría en el dispositivo.")
        }
        return .available
    }

    static let minimumShots = 32
    static let shotsPerRevolution = 36

    var autoCaptureInterval: TimeInterval = 2.0

    var shouldChangeElevation: Bool {
        shotCount >= Self.shotsPerRevolution
    }

    // MARK: - Observable State

    private(set) var phase: ScanPhase = .idle
    private(set) var shotCount = 0
    private(set) var isAutoCapturing = false
    private(set) var deliversDepth = false
    private(set) var megapixels = 0
    private(set) var captureError: String?
    private(set) var isLocked = false
    private(set) var lockState: LockState = .unlocked
    private(set) var warnings: [String] = []

    enum LockState: Equatable {
        case unlocked
        case locking
        case locked
        case failed
    }

    private(set) var rejectedShots = 0
    private(set) var lastRejectionReason: String?

    var objectMaskRect: CGRect?

    var session: AVCaptureSession? { coordinator?.session }
    var canFinish: Bool { shotCount >= Self.minimumShots }

    // MARK: - Private

    private let storage: ScanStorage
    private let reconstructor = PhotogrammetryReconstructor()
    private var coordinator: PhotoCaptureCoordinator?
    private var workspace: ScanWorkspace?
    private var autoCaptureTask: Task<Void, Never>?

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

        let coordinator = PhotoCaptureCoordinator(
            imagesDirectory: workspace.imagesURL,
            onShotSaved: { [weak self] index in
                Task { @MainActor in self?.shotSaved(index) }
            },
            onShotRejected: { [weak self] reason in
                Task { @MainActor in
                    self?.rejectedShots += 1
                    self?.lastRejectionReason = reason
                }
            },
            onFailure: { [weak self] message in
                Task { @MainActor in self?.captureError = message }
            }
        )

        do {
            try coordinator.configure()
        } catch {
            storage.discard(workspace)
            self.workspace = nil
            phase = .failed(message: error.localizedDescription)
            throw ScanEngineError.sessionUnavailable(error.localizedDescription)
        }

        self.coordinator = coordinator
        deliversDepth = coordinator.deliversDepth
        megapixels = coordinator.megapixels
        coordinator.start()

        phase = .capturing(shots: 0, limit: 0)
    }

    func finish() async throws -> ScanRecord {
        guard let coordinator, let workspace else {
            throw ScanEngineError.sessionUnavailable("No hay sesión activa.")
        }

        stopAutoCapture()
        coordinator.stop()

        guard shotCount > 0 else {
            phase = .failed(message: "No se capturó ninguna imagen.")
            throw ScanEngineError.noImagesCaptured
        }

        let capturedShots = shotCount
        phase = .reconstructing(ReconstructionProgress())

        let output: PhotogrammetryReconstructor.Output
        do {
            output = try await reconstructor.reconstruct(
                workspace: workspace,
                detail: .reduced,
                maskRect: objectMaskRect,
                onWarning: { [weak self] note in
                    self?.warnings.append(note)
                }
            ) { [weak self] progress in
                self?.phase = .reconstructing(progress)
            }
        } catch {
            phase = .failed(message: error.localizedDescription)
            throw error
        }

        if let poses = output.poses {
            warnings.append(contentsOf: poses.advice)
        }

        let record = ScanRecord(
            id: workspace.id,
            name: Self.defaultName(for: Date()),
            engine: Self.kind,
            isMetricallyScaled: deliversDepth,
            imageCount: capturedShots,
            detail: .reduced,
            summary: output.poses?.summaryText
        )
        storage.commit(record, workspace: workspace)

        teardown()
        phase = .done(record)
        return record
    }

    func cancel() {
        stopAutoCapture()
        coordinator?.stop()
        teardown()
        if let workspace {
            storage.discard(workspace)
            self.workspace = nil
        }
        phase = .cancelled
    }

    // MARK: - Controls

    func lockCameraSettings() {
        guard lockState != .locking else { return }
        lockState = .locking
        coordinator?.lockCameraSettings { [weak self] success in
            Task { @MainActor in
                self?.isLocked = success
                self?.lockState = success ? .locked : .failed
            }
        }
    }

    func captureNow() {
        coordinator?.capture()
    }

    func toggleAutoCapture() {
        isAutoCapturing ? stopAutoCapture() : startAutoCapture()
    }

    private func startAutoCapture() {
        guard coordinator != nil else { return }
        if !isLocked { lockCameraSettings() }
        isAutoCapturing = true
        autoCaptureTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isAutoCapturing else { return }
                self.coordinator?.capture()
                try? await Task.sleep(for: .seconds(self.autoCaptureInterval))
            }
        }
    }

    private func stopAutoCapture() {
        isAutoCapturing = false
        autoCaptureTask?.cancel()
        autoCaptureTask = nil
    }

    private func shotSaved(_ index: Int) {
        shotCount = index
        captureError = nil
        if case .capturing = phase {
            phase = .capturing(shots: index, limit: 0)
        }
    }

    private func teardown() {
        stopAutoCapture()
        coordinator = nil
        captureError = nil
    }

    private static func defaultName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "d MMM HH:mm"
        return "Mesa \(formatter.string(from: date))"
    }
}
