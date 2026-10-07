import ARKit
import Foundation
import Observation
import simd
import os

/// TrueDepth front-sensor structured light point cloud scanner
@MainActor
@Observable
final class TrueDepthEngine: ScanEngine {
    private static let logger = Logger(subsystem: "com.vileroccietti.Fusion", category: "truedepth")

    static let kind: ScanEngineKind = .trueDepth

    static var availability: EngineAvailability {
        guard ARFaceTrackingConfiguration.isSupported else {
            return .unsupportedDevice(reason: "No se detectó el sensor TrueDepth.")
        }
        guard ARFaceTrackingConfiguration.supportsWorldTracking else {
            return .unsupportedDevice(reason: "El dispositivo no soporta seguimiento del mundo con la cámara frontal.")
        }
        return .available
    }

    // MARK: - Observable State

    private(set) var phase: ScanPhase = .idle
    private(set) var snapshot = DepthFrameReceiver.Snapshot()
    private(set) var trackingWarning: String?

    var processorOptions = DepthFrameProcessor.Options() {
        didSet { restartIfRunning() }
    }

    var regionHalfExtent: Float = 0.15
    private(set) var session: ARSession?

    // MARK: - Private

    private let storage: ScanStorage
    private var receiver: DepthFrameReceiver?
    private var workspace: ScanWorkspace?
    private let frameQueue = DispatchQueue(label: "com.vileroccietti.Fusion.depth", qos: .userInitiated)

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

        let receiver = DepthFrameReceiver(
            processor: DepthFrameProcessor(options: processorOptions),
            voxelSize: DepthPointCloud.defaultVoxelSize,
            onSnapshot: { [weak self] snapshot in
                Task { @MainActor in self?.apply(snapshot) }
            },
            onTrackingChange: { [weak self] state in
                Task { @MainActor in self?.apply(trackingState: state) }
            }
        )
        self.receiver = receiver

        let session = ARSession()
        session.delegateQueue = frameQueue
        session.delegate = receiver
        self.session = session

        let configuration = ARFaceTrackingConfiguration()
        configuration.isWorldTrackingEnabled = true
        configuration.maximumNumberOfTrackedFaces = 0

        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        phase = .capturing(shots: 0, limit: 0)
        Self.logger.info("Sesión TrueDepth iniciada")
    }

    func finish() async throws -> ScanRecord {
        guard let session, let receiver, let workspace else {
            throw ScanEngineError.sessionUnavailable("No hay sesión activa.")
        }

        phase = .reconstructing(ReconstructionProgress(fraction: 0.2, stage: .pointCloudGeneration))
        session.pause()

        let cloud = frameQueue.sync { receiver.finalise() }

        guard !cloud.isEmpty else {
            phase = .failed(message: "No se recopilaron muestras de profundidad válidas. Mantente a una distancia de 20 a 100 cm.")
            throw ScanEngineError.reconstructionFailed("La nube de puntos está vacía.")
        }

        phase = .reconstructing(ReconstructionProgress(fraction: 0.7, stage: .optimization))

        let points = cloud.points
        let outputURL = workspace.root.appending(path: "cloud.ply", directoryHint: .notDirectory)

        do {
            try await Task.detached(priority: .userInitiated) {
                try PointCloudFile.write(points: points, to: outputURL)
            }.value
        } catch {
            phase = .failed(message: error.localizedDescription)
            throw ScanEngineError.reconstructionFailed(error.localizedDescription)
        }

        let dimensions = cloud.dimensions.map { size in
            [Int((size.x * 1000).rounded()), Int((size.y * 1000).rounded()), Int((size.z * 1000).rounded())]
        }

        let record = ScanRecord(
            id: workspace.id,
            name: Self.defaultName(for: Date()),
            engine: Self.kind,
            modelFileName: "cloud.ply",
            isMetricallyScaled: true,
            pointCount: points.count,
            dimensionsMillimetres: dimensions
        )
        storage.commit(record, workspace: workspace)

        teardown()
        phase = .done(record)
        return record
    }

    func cancel() {
        session?.pause()
        teardown()
        if let workspace {
            storage.discard(workspace)
            self.workspace = nil
        }
        phase = .cancelled
    }

    func lockRegion() {
        guard let aim = snapshot.aimPoint, let receiver else { return }
        let region = DepthFrameProcessor.Region(center: aim, halfExtent: regionHalfExtent)
        frameQueue.async { receiver.setRegion(region) }
    }

    func clearRegion() {
        guard let receiver else { return }
        frameQueue.async { receiver.setRegion(nil) }
    }

    var distanceAdvice: (text: String, isGood: Bool)? {
        guard let depth = snapshot.medianDepth else { return nil }
        switch depth {
        case ..<0.22: return ("Demasiado cerca — el sensor no puede medir", false)
        case 0.22..<0.35: return ("Distancia ideal", true)
        case 0.35..<0.55: return ("Acércate un poco para maximizar detalle", false)
        default: return ("Demasiado lejos — acércate al objeto", false)
        }
    }

    private func apply(_ snapshot: DepthFrameReceiver.Snapshot) {
        self.snapshot = snapshot
        if case .capturing = phase {
            phase = .capturing(shots: snapshot.pointCount, limit: 0)
        }
    }

    private func apply(trackingState: ARCamera.TrackingState) {
        switch trackingState {
        case .normal:
            trackingWarning = nil
        case .notAvailable:
            trackingWarning = "Sin seguimiento de posición — mueve el dispositivo"
        case .limited(let reason):
            switch reason {
            case .initializing:
                trackingWarning = "Iniciando seguimiento..."
            case .relocalizing:
                trackingWarning = "Relocalizando posición..."
            case .excessiveMotion:
                trackingWarning = "Movimiento muy rápido — muévete más lento"
            case .insufficientFeatures:
                trackingWarning = "La habitación detrás de ti carece de textura — la posición depende de la cámara trasera"
            @unknown default:
                trackingWarning = "Seguimiento débil"
            }
        }
    }

    private func restartIfRunning() {
        guard case .capturing = phase else { return }
        session?.pause()
        if let workspace { storage.discard(workspace) }
        workspace = nil
        session = nil
        receiver = nil
        snapshot = DepthFrameReceiver.Snapshot()
        try? start()
    }

    private func teardown() {
        session?.delegate = nil
        session = nil
        receiver = nil
        trackingWarning = nil
    }

    private static func defaultName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "d MMM HH:mm"
        return "Profundidad \(formatter.string(from: date))"
    }
}
