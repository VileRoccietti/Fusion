import Foundation
import RoomPlan

/// USD export styles for RoomPlan
enum RoomExportStyle: String, CaseIterable, Identifiable, Sendable {
    /// Walls, doors, windows, and furniture as clean parametric primitives
    case parametric
    /// Raw triangle mesh of physical surfaces captured by LiDAR
    case mesh

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .parametric: "Arquitectónico (Cajas Limpias)"
        case .mesh: "Malla LiDAR Real"
        }
    }

    var explanation: String {
        switch self {
        case .parametric:
            "Paredes, puertas, ventanas y muebles clasificados como cajas paramétricas limpias. Archivo compacto, ideal para planos y CAD."
        case .mesh:
            "Superficie real medida por el sensor LiDAR con todos los detalles, relieves e irregularidades."
        }
    }

    var options: CapturedRoom.USDExportOptions {
        switch self {
        case .parametric: .parametric
        case .mesh: .mesh
        }
    }
}
