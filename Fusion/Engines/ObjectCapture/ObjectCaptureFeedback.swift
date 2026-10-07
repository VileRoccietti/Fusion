import RealityKit
import SwiftUI

extension ObjectCaptureSession.Feedback {
    /// Live feedback coaching in natural Spanish
    var hint: String? {
        switch self {
        case .objectTooFar:
            "Acércate más al objeto"
        case .objectTooClose:
            "Aléjate un poco del objeto"
        case .movingTooFast:
            "Muévete más despacio"
        case .environmentTooDark:
            "El entorno está muy oscuro — añade más luz"
        case .environmentLowLight:
            "Iluminación baja, el detalle fino podría perderse"
        case .outOfFieldOfView:
            "Mantén el objeto dentro del encuadre"
        case .objectNotFlippable:
            "Este objeto no se puede voltear — continúa orbitando"
        case .overCapturing:
            nil
        default:
            nil
        }
    }
}

extension ObjectCaptureSession.Tracking {
    var isReliable: Bool {
        if case .normal = self { return true }
        return false
    }

    /// Tracking status warning in natural Spanish
    var warning: String? {
        switch self {
        case .normal:
            nil
        case .notAvailable:
            "Sin seguimiento de posición — mueve el dispositivo para reenganchar"
        case .limited(let reason):
            switch reason {
            case .initializing:
                nil
            case .relocalizing:
                "Relocalizando posición espacial — muévete despacio"
            case .excessiveMotion:
                "Movimiento demasiado rápido — muévete más suavemente"
            case .insufficientFeatures:
                "Faltan rasgos distintivos en la superficie — coloca el objeto sobre una superficie con textura"
            @unknown default:
                "Seguimiento espacial limitado"
            }
        @unknown default:
            nil
        }
    }
}
