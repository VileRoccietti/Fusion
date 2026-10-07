import Foundation
import Observation
import RoomPlan
import os

/// Apple RoomPlan LiDAR room capture engine
@MainActor
@Observable
final class RoomCaptureEngine: ScanEngine {
    private static let logger = Logger(subsystem: "com.vileroccietti.Fusion", category: "roomplan")

    static let kind: ScanEngineKind = .roomPlan

    static var availability: EngineAvailability {
        guard RoomCaptureSession.isSupported else {
            return .unsupportedDevice(reason: "El escaneo de habitaciones requiere LiDAR; este dispositivo no lo soporta.")
        }
        return .available
    }

    // MARK: - Observable State

    private(set) var phase: ScanPhase = .idle
    private(set) var summary: RoomSummary?

    var exportStyle: RoomExportStyle = .parametric
    var capturesPhotographicModel = false

    private(set) var photographicRecord: ScanRecord?
    private(set) var photographicNote: String?

    var keyframeCount: Int { keyframeCollector?.savedCount ?? 0 }
    var frameResolution: Int? { keyframeCollector?.frameResolution }
    var wallSectors: Set<Int> { keyframeCollector?.wallSectors ?? [] }
    var floorSectors: Set<Int> { keyframeCollector?.floorSectors ?? [] }
    var heading: Double? { keyframeCollector?.heading }
    private(set) var cameraDiagnostic: String?

    let captureView = RoomCaptureView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))

    // MARK: - Private

    private let storage: ScanStorage
    private let reconstructor = PhotogrammetryReconstructor()
    private let delegateProxy = RoomCaptureDelegateProxy()
    private var workspace: ScanWorkspace?
    private var hasStartedSession = false
    private var cameraWatchdog: Task<Void, Never>?
    private var photoWorkspace: ScanWorkspace?
    private var keyframeCollector: RoomKeyframeCollector?

    init(storage: ScanStorage) {
        self.storage = storage
        captureView.delegate = delegateProxy
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
        phase = .preparing
    }

    func beginCapture() {
        guard !hasStartedSession, workspace != nil else { return }
        hasStartedSession = true

        var configuration = RoomCaptureSession.Configuration()
        configuration.isCoachingEnabled = true
        captureView.captureSession.run(configuration: configuration)

        if capturesPhotographicModel {
            startKeyframeCollection()
        }

        phase = .capturing(shots: 0, limit: 0)
        startCameraWatchdog()
    }

    private func startKeyframeCollection() {
        do {
            let photoWorkspace = try storage.makeWorkspace()
            self.photoWorkspace = photoWorkspace
            let collector = RoomKeyframeCollector(directory: photoWorkspace.imagesURL)
            collector.start(arSession: captureView.captureSession.arSession)
            keyframeCollector = collector
        } catch {
            Self.logger.error("No se pudo iniciar el recolector de fotos: \(error.localizedDescription, privacy: .public)")
            photographicNote = "No se pudo habilitar el modelo fotográfico: \(error.localizedDescription)"
        }
    }

    func finish() async throws -> ScanRecord {
        guard let workspace else {
            throw ScanEngineError.sessionUnavailable("No hay sesión activa.")
        }
        guard hasStartedSession else {
            throw ScanEngineError.sessionUnavailable("La sesión de cámara no ha comenzado.")
        }

        cameraWatchdog?.cancel()
        cameraWatchdog = nil
        keyframeCollector?.stop()
        phase = .reconstructing(ReconstructionProgress())

        let room: CapturedRoom
        do {
            room = try await stopAndProcess()
        } catch {
            phase = .failed(message: error.localizedDescription)
            throw error
        }

        let style = exportStyle
        let modelURL = workspace.modelURL
        do {
            try await Task.detached(priority: .userInitiated) {
                try room.export(to: modelURL, exportOptions: style.options)
            }.value
        } catch {
            Self.logger.error("No se pudo exportar la habitación: \(error.localizedDescription, privacy: .public)")
            phase = .failed(message: error.localizedDescription)
            throw ScanEngineError.reconstructionFailed(error.localizedDescription)
        }

        let summary = RoomSummary(room: room)
        self.summary = summary

        let record = ScanRecord(
            id: workspace.id,
            name: Self.defaultName(for: Date()),
            engine: Self.kind,
            isMetricallyScaled: true,
            dimensionsMillimetres: summary.dimensionsMillimetres,
            summary: summary.text
        )
        storage.commit(record, workspace: workspace)
        self.workspace = nil

        await reconstructPhotographicModel(roomName: record.name)

        phase = .done(record)
        return record
    }

    private func reconstructPhotographicModel(roomName: String) async {
        guard let photoWorkspace, let collector = keyframeCollector else { return }
        defer {
            self.photoWorkspace = nil
            keyframeCollector = nil
        }

        let frames = collector.savedCount
        guard frames >= RoomKeyframeCollector.minimumFrames else {
            storage.discard(photoWorkspace)
            photographicNote = "No se capturaron suficientes fotos para el modelo texturizado (\(frames)/\(RoomKeyframeCollector.minimumFrames))."
            return
        }

        do {
            let output = try await reconstructor.reconstruct(
                workspace: photoWorkspace,
                detail: .reduced,
                enableObjectMasking: false,
                framing: .interior,
                onWarning: { [weak self] note in
                    self?.photographicNote = note
                }
            ) { [weak self] progress in
                self?.phase = .reconstructing(progress)
            }

            let photoRecord = ScanRecord(
                id: photoWorkspace.id,
                name: "\(roomName) · Texturizado",
                engine: Self.kind,
                isMetricallyScaled: false,
                imageCount: frames,
                detail: .reduced,
                summary: output.poses?.summaryText
            )
            storage.commit(photoRecord, workspace: photoWorkspace)
            photographicRecord = photoRecord

            if let advice = output.poses?.advice, !advice.isEmpty {
                photographicNote = advice.joined(separator: " ")
            }
        } catch {
            Self.logger.error("Reconstrucción fotográfica fallida: \(error.localizedDescription, privacy: .public)")
            storage.discard(photoWorkspace)
            photographicNote = "No se pudo generar el modelo fotográfico: \(error.localizedDescription)"
        }
    }

    func cancel() {
        cameraWatchdog?.cancel()
        cameraWatchdog = nil
        keyframeCollector?.stop()
        keyframeCollector = nil
        if let photoWorkspace {
            storage.discard(photoWorkspace)
            self.photoWorkspace = nil
        }
        delegateProxy.onProcessed = nil
        if hasStartedSession {
            captureView.captureSession.stop()
        }
        if let workspace {
            storage.discard(workspace)
            self.workspace = nil
        }
        phase = .cancelled
    }

    private func startCameraWatchdog() {
        cameraWatchdog = Task { [weak self] in
            var elapsed = 0.0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                elapsed += 0.5
                guard let self else { return }
                guard case .capturing = phase else { continue }

                if captureView.captureSession.arSession.currentFrame == nil {
                    if elapsed >= 3 {
                        cameraDiagnostic = "La cámara no está generando fotogramas — comprueba los permisos de ARKit."
                    }
                } else {
                    cameraDiagnostic = nil
                    return
                }
            }
        }
    }

    private func stopAndProcess() async throws -> CapturedRoom {
        try await withCheckedThrowingContinuation { continuation in
            delegateProxy.onProcessed = { result in
                continuation.resume(with: result)
            }
            captureView.captureSession.stop()
        }
    }

    private static func defaultName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "d MMM HH:mm"
        return "Habitación \(formatter.string(from: date))"
    }
}

@objc(OSRoomCaptureDelegateProxy)
private final class RoomCaptureDelegateProxy: NSObject, RoomCaptureViewDelegate, @unchecked Sendable {
    var onProcessed: (@MainActor @Sendable (Result<CapturedRoom, ScanEngineError>) -> Void)?

    override init() { super.init() }

    required init?(coder: NSCoder) { nil }
    func encode(with coder: NSCoder) {}

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: (any Error)?) -> Bool {
        guard onProcessed != nil else { return false }
        if let error {
            deliver(.failure(.reconstructionFailed(error.localizedDescription)))
            return false
        }
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: (any Error)?) {
        if let error {
            deliver(.failure(.reconstructionFailed(error.localizedDescription)))
        } else {
            deliver(.success(processedResult))
        }
    }

    private func deliver(_ result: Result<CapturedRoom, ScanEngineError>) {
        guard let handler = onProcessed else { return }
        onProcessed = nil
        Task { @MainActor in handler(result) }
    }
}
