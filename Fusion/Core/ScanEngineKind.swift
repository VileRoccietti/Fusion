import Foundation

/// Available scanning engine modes
enum ScanEngineKind: String, Codable, CaseIterable, Identifiable, Sendable {
    /// RealityKit guided photogrammetry with LiDAR
    case objectCapture
    /// Fixed device on tripod with rotating object (PhotogrammetrySession)
    case turntable
    /// Front TrueDepth structured light sensor
    case trueDepth
    /// Apple RoomPlan LiDAR room scanner
    case roomPlan

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .objectCapture: "Fotogrametría Guiada"
        case .turntable: "Mesa Giratoria (Trípode)"
        case .trueDepth: "TrueDepth (Sensor Frontal)"
        case .roomPlan: "Habitación (RoomPlan LiDAR)"
        }
    }

    var symbolName: String {
        switch self {
        case .objectCapture: "cube.transparent"
        case .turntable: "rotate.3d"
        case .trueDepth: "sensor.tag.radiowaves.forward.fill"
        case .roomPlan: "door.left.hand.open"
        }
    }

    var tagline: String {
        switch self {
        case .objectCapture: "Orbita alrededor del objeto con guía LiDAR en tiempo real."
        case .turntable: "iPhone en trípode, objeto girando. Captura automática y sin desenfoque."
        case .trueDepth: "Nube de puntos métrica de alta densidad para objetos pequeños."
        case .roomPlan: "Clasificación LiDAR de paredes, puertas, ventanas y mobiliario."
        }
    }

    var maturity: Maturity {
        switch self {
        case .objectCapture, .roomPlan: .stable
        case .turntable, .trueDepth: .proBeta
        }
    }

    var isImplemented: Bool { true }

    enum Maturity {
        case stable
        case proBeta

        var badge: String? {
            switch self {
            case .stable: nil
            case .proBeta: "PRO BETA"
            }
        }
    }
}
