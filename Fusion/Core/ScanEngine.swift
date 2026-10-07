import Foundation

/// Lifecycle phases of any scan session
enum ScanPhase: Equatable {
    case idle
    case preparing
    case readyToDetect
    case framing
    case capturing(shots: Int, limit: Int)
    case reconstructing(ReconstructionProgress)
    case done(ScanRecord)
    case failed(message: String)
    case cancelled
}

/// Availability evaluation for an engine on current device
enum EngineAvailability: Equatable {
    case available
    case unsupportedDevice(reason: String)

    var isUsable: Bool {
        if case .available = self { return true }
        return false
    }

    var blockedReason: String? {
        switch self {
        case .available: return nil
        case .unsupportedDevice(let reason): return reason
        }
    }
}

/// Scanning errors
enum ScanEngineError: LocalizedError {
    case sessionUnavailable(String)
    case noImagesCaptured
    case reconstructionFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .sessionUnavailable(let reason): "Sesión no disponible: \(reason)"
        case .noImagesCaptured: "No se capturó ninguna imagen válida."
        case .reconstructionFailed(let reason): "Error de reconstrucción 3D: \(reason)"
        case .cancelled: "El escaneo fue cancelado."
        }
    }
}

/// Disk workspace for an in-flight scan
struct ScanWorkspace: Sendable {
    let id: UUID
    let root: URL

    var imagesURL: URL {
        root.appending(path: "images", directoryHint: .isDirectory)
    }

    var checkpointURL: URL {
        root.appending(path: "checkpoints", directoryHint: .isDirectory)
    }

    var modelURL: URL {
        root.appending(path: "model.usdz", directoryHint: .notDirectory)
    }
}

/// Protocol implemented by all 4 scan engines
@MainActor
protocol ScanEngine: AnyObject {
    static var kind: ScanEngineKind { get }
    static var availability: EngineAvailability { get }

    var phase: ScanPhase { get }

    func start() throws
    func finish() async throws -> ScanRecord
    func cancel()
}
