import Foundation

/// Object characteristics questionnaire for intelligent scan mode recommendation
struct ObjectProfile: Equatable {
    var size: Size = .small
    var finish: Finish = .matte
    var pattern: Pattern = .some

    enum Size: String, CaseIterable, Identifiable {
        case tiny, small, medium, large
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .tiny: "Menor a 5 cm (Muy pequeño)"
            case .small: "5 – 30 cm (Objeto de mesa)"
            case .medium: "30 cm – 1 m (Caja / Escultura)"
            case .large: "Mayor a 1 m (Mobiliario / Habitación)"
            }
        }
    }

    enum Finish: String, CaseIterable, Identifiable {
        case matte, satin, glossy
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .matte: "Mate (Sin brillo)"
            case .satin: "Semibrillante"
            case .glossy: "Brillante / Metálico / Vidrio"
            }
        }
    }

    enum Pattern: String, CaseIterable, Identifiable {
        case rich, some, none
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .rich: "Mucho relieve / Textura rica"
            case .some: "Textura moderada"
            case .none: "Liso / Un solo color uniforme"
            }
        }
    }
}

struct ModeRecommendation: Equatable {
    enum Strength: Equatable {
        case strong
        case qualified
        case fallback
    }

    let kind: ScanEngineKind
    let strength: Strength
    let rationale: String
    var warnings: [String] = []
    var tips: [String] = []
}

extension ObjectProfile {
    func recommendation(availableKinds: Set<ScanEngineKind>) -> ModeRecommendation {
        let trueDepthUsable = availableKinds.contains(.trueDepth)

        var warnings: [String] = []
        var tips: [String] = []

        if finish == .glossy {
            warnings.append("Las superficies brillantes o metálicas reflejan luz variable según el ángulo, lo cual dificulta la correlación entre fotogramas.")
            tips.append("Consejo: Aplica un aerosol de escaneo 3D sublimable o polvo mate temporal para maximizar la nitidez de la malla.")
        }

        if size == .tiny {
            warnings.append("Objetos menores a 5 cm están en el límite de resolución de los sensores ópticos de teléfonos.")
            tips.append("Coloca el objeto sobre una base con patrón contrastante y acércate con buena iluminación.")
        }

        if size == .large {
            tips.append("En objetos grandes realiza 2 o 3 órbitas a diferentes alturas (arriba, medio y abajo).")
        }

        if size == .tiny || size == .small {
            tips.append("Para objetos de mesa, el modo Mesa Giratoria con trípode produce resultados extraordinariamente nítidos.")
        }

        // Featureless surface
        if pattern == .none {
            if trueDepthUsable {
                return ModeRecommendation(
                    kind: .trueDepth,
                    strength: size == .tiny ? .qualified : .strong,
                    rationale: "El objeto tiene una superficie lisa sin textura. La fotogrametría requiere textura para inferir geometría; TrueDepth utiliza un proyector de luz infrarroja estructurada independiente del color visual.",
                    warnings: warnings,
                    tips: tips
                )
            }

            return ModeRecommendation(
                kind: .objectCapture,
                strength: .fallback,
                rationale: "Superficie lisa: la fotogrametría tendrá dificultades salvo que agregues marcas o puntos de referencia.",
                warnings: warnings,
                tips: tips
            )
        }

        // Matte with rich texture
        if finish == .matte, pattern == .rich {
            return ModeRecommendation(
                kind: .objectCapture,
                strength: .strong,
                rationale: "Superficie mate y con textura rica: el escenario perfecto para Object Capture con LiDAR. Generará máxima fidelidad geométrica y texturas 4K.",
                warnings: warnings,
                tips: tips
            )
        }

        return ModeRecommendation(
            kind: .objectCapture,
            strength: finish == .glossy ? .qualified : .strong,
            rationale: "La superficie cuenta con suficientes rasgos característicos para un escaneo fotogramétrico de alta calidad.",
            warnings: warnings,
            tips: tips
        )
    }
}
