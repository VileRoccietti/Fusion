import SwiftUI

/// 3D Inspection and viewport rendering modes
enum RenderMode: String, CaseIterable, Identifiable, Sendable {
    case pbr
    case wireframe
    case normals
    case pointCloud
    case clay
    case unlit

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pbr: "PBR Realista"
        case .wireframe: "Malla Wireframe"
        case .normals: "Normales de Superficie"
        case .pointCloud: "Nube de Puntos"
        case .clay: "Arcilla (MatCap)"
        case .unlit: "Sin Iluminación (Albedo)"
        }
    }

    var iconName: String {
        switch self {
        case .pbr: "cube.fill"
        case .wireframe: "square.dashed"
        case .normals: "compass.drawing"
        case .pointCloud: "circle.dotted"
        case .clay: "paintbrush.fill"
        case .unlit: "sun.max"
        }
    }

    var explanation: String {
        switch self {
        case .pbr: "Texturizado completo PBR con reflejos, rugosidad y sombras en tiempo real."
        case .wireframe: "Visualiza la densidad poligonal y la topología de los triángulos."
        case .normals: "Mapa de colores de orientación de normales para detectar caras invertidas."
        case .pointCloud: "Muestra únicamente los vértices medidos por el escáner."
        case .clay: "Acabado neutro mate para evaluar la geometría sin interferencia de texturas."
        case .unlit: "Color base puro de la textura sin luces ni sombras simuladas."
        }
    }
}
