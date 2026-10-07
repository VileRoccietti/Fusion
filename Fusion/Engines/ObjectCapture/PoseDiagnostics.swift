import Foundation
import RealityKit
import simd

/// Solved camera poses and reconstruction diagnostics
struct PoseDiagnostics: Sendable {

    enum Framing: Sendable {
        /// Cameras surround the subject (orbit / turntable)
        case orbit
        /// Cameras move inside the subject (room walk)
        case interior
    }

    let framing: Framing
    let solvedSamples: Int
    let totalSamples: Int
    let azimuthCoverageDegrees: Int
    let elevationSpreadDegrees: Int

    private static let azimuthBinCount = 24

    init(poses: PhotogrammetrySession.Poses, totalSamples: Int, framing: Framing) {
        let positions = poses.posesBySample.values.map(\.translation)
        solvedSamples = positions.count
        self.totalSamples = totalSamples
        self.framing = framing

        guard framing == .orbit else {
            azimuthCoverageDegrees = 0
            elevationSpreadDegrees = 0
            return
        }

        guard positions.count >= 2 else {
            azimuthCoverageDegrees = 0
            elevationSpreadDegrees = 0
            return
        }

        let centroid = positions.reduce(SIMD3<Float>.zero, +) / Float(positions.count)

        var occupiedBins = Set<Int>()
        var minimumElevation = Float.greatestFiniteMagnitude
        var maximumElevation = -Float.greatestFiniteMagnitude

        for position in positions {
            let offset = position - centroid
            let length = simd_length(offset)
            guard length > 1e-5 else { continue }

            let azimuth = atan2(offset.z, offset.x)
            let normalised = (azimuth + .pi) / (2 * .pi)
            let bin = min(Self.azimuthBinCount - 1, Int(normalised * Float(Self.azimuthBinCount)))
            occupiedBins.insert(bin)

            let elevation = asin(max(-1, min(1, offset.y / length)))
            minimumElevation = min(minimumElevation, elevation)
            maximumElevation = max(maximumElevation, elevation)
        }

        let degreesPerBin = 360 / Self.azimuthBinCount
        azimuthCoverageDegrees = occupiedBins.count * degreesPerBin

        if maximumElevation >= minimumElevation {
            let spread = (maximumElevation - minimumElevation) * 180 / .pi
            elevationSpreadDegrees = Int(spread.rounded())
        } else {
            elevationSpreadDegrees = 0
        }
    }

    var summaryText: String {
        let alignment = "\(solvedSamples)/\(totalSamples) fotos alineadas"
        guard framing == .orbit else { return alignment }
        return "\(alignment) · horizontal \(azimuthCoverageDegrees)° · vertical \(elevationSpreadDegrees)°"
    }

    var advice: [String] {
        var notes: [String] = []

        if totalSamples > 0, solvedSamples < (totalSamples * 4) / 5 {
            let dropped = totalSamples - solvedSamples
            switch framing {
            case .orbit:
                notes.append("\(dropped) fotos no pudieron alinearse y no se incluyeron en el modelo. Causa común: sombras cambiantes al rotar el objeto o luz no uniforme. Se recomienda luz suave y difusa.")
            case .interior:
                notes.append("\(dropped) tomas no se alinearon (solo el \(totalSamples > 0 ? solvedSamples * 100 / totalSamples : 0)% fue utilizado). Al caminar, la causa más común es desenfoque por movimiento rápido. Gira más despacio y asegura buena luz.")
            }
        }

        switch framing {
        case .orbit:
            if azimuthCoverageDegrees < 300 {
                notes.append("Cobertura horizontal de \(azimuthCoverageDegrees)° — la vuelta de 360° quedó incompleta. En la zona no cubierta la geometría puede presentar huecos.")
            }

            if elevationSpreadDegrees < 15 {
                notes.append("Todas las fotos se tomaron casi a la misma altura (\(elevationSpreadDegrees)° de variación vertical). Se recomienda una segunda pasada variando la altura o inclinación del iPhone.")
            }

        case .interior:
            if solvedSamples >= (totalSamples * 4) / 5 {
                notes.append("Captura excelente: fotos perfectamente alineadas. Para una malla con millones de polígonos, exporte el archivo ZIP y procese con .raw en una Mac.")
            }
        }

        return notes
    }
}
