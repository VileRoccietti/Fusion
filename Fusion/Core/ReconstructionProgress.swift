import Foundation

/// Pipeline stage during 3D reconstruction
enum ReconstructionStage: Int, CaseIterable, Identifiable, Sendable {
    case preProcessing = 0
    case imageAlignment = 1
    case pointCloudGeneration = 2
    case meshGeneration = 3
    case textureMapping = 4
    case optimization = 5

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .preProcessing: "Preprocesamiento de imágenes"
        case .imageAlignment: "Alineación de cámaras y poses"
        case .pointCloudGeneration: "Generación de nube de puntos"
        case .meshGeneration: "Generación de malla poligonal"
        case .textureMapping: "Mapeo y horneado de texturas PBR"
        case .optimization: "Optimización y compresión del modelo"
        }
    }
}

/// Unified progress tracking struct
struct ReconstructionProgress: Equatable, Sendable {
    var fraction: Double
    var stage: ReconstructionStage?
    var estimatedRemaining: TimeInterval?

    init(fraction: Double = 0, stage: ReconstructionStage? = nil, estimatedRemaining: TimeInterval? = nil) {
        self.fraction = fraction
        self.stage = stage
        self.estimatedRemaining = estimatedRemaining
    }

    var remainingText: String? {
        guard let estimatedRemaining, estimatedRemaining > 0 else { return nil }
        let minutes = Int(estimatedRemaining) / 60
        let seconds = Int(estimatedRemaining) % 60
        if minutes > 0 {
            return String(format: "%d min %02d s", minutes, seconds)
        } else {
            return String(format: "%d s", seconds)
        }
    }
}
