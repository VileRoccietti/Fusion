import Foundation
import ModelIO
import os

enum MeshExportFormat: String, CaseIterable, Identifiable, Sendable {
    /// Native Apple RealityKit output with full PBR materials
    case usdz
    /// Standard mesh interchange format for Blender, Maya, ZBrush, 3ds Max
    case obj
    /// Standard stereolithography format for 3D printing (Bambu Studio, PrusaSlicer, Cura)
    case stl
    /// Point cloud and polygon geometry format for CloudCompare, MeshLab
    case ply

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .usdz: "USDZ (AR Quick Look)"
        case .obj: "OBJ (Wavefront + MTL)"
        case .stl: "STL (Impresión 3D)"
        case .ply: "PLY (Nube / Malla)"
        }
    }

    var fileExtension: String { rawValue }

    var explanation: String {
        switch self {
        case .usdz: "Ecosistema Apple, AR Quick Look, visionOS. Formato nativo con materiales PBR y físicas."
        case .obj: "Formato estándar para Blender, Unreal Engine, Unity, ZBrush. Incluye materiales y geometría."
        case .stl: "Ideal para impresión 3D (Bambu Studio, Cura, PrusaSlicer). Geometría pura a escala métrica milimétrica."
        case .ply: "Nube de puntos y malla densa para escaneado láser, fotogrametría y MeshLab."
        }
    }

    /// True if format preserves only geometry without textures/materials
    var isGeometryOnly: Bool {
        switch self {
        case .usdz, .obj: false
        case .ply, .stl: true
        }
    }
}

enum MeshExportError: LocalizedError {
    case sourceMissing
    case formatUnsupported(MeshExportFormat)
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .sourceMissing:
            "El archivo del modelo no existe o fue eliminado."
        case .formatUnsupported(let format):
            "El formato \(format.displayName) no es compatible con el exportador del sistema."
        case .conversionFailed(let detail):
            "Error en la conversión del modelo 3D: \(detail)"
        }
    }
}

enum MeshExporter {
    private static let logger = Logger(subsystem: "com.vileroccietti.Fusion", category: "export")

    /// Converts a model USDZ into target format, returning the exported file URL
    static func export(
        modelAt sourceURL: URL,
        as format: MeshExportFormat,
        namedLike baseName: String
    ) async throws -> URL {

        guard FileManager.default.fileExists(atPath: sourceURL.path(percentEncoded: false)) else {
            throw MeshExportError.sourceMissing
        }

        let safeName = baseName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let fileName = safeName.isEmpty ? "modelo" : safeName

        let destination = FileManager.default.temporaryDirectory
            .appending(path: "\(fileName).\(format.rawValue)", directoryHint: .notDirectory)
        try? FileManager.default.removeItem(at: destination)

        if format == .usdz {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return destination
        }

        guard MDLAsset.canExportFileExtension(format.rawValue) else {
            throw MeshExportError.formatUnsupported(format)
        }

        try await Task.detached(priority: .userInitiated) {
            let asset = MDLAsset(url: sourceURL)
            guard asset.count > 0 else {
                throw MeshExportError.conversionFailed("El modelo no contiene ninguna geometría exportable.")
            }
            do {
                try asset.export(to: destination)
            } catch {
                throw MeshExportError.conversionFailed(error.localizedDescription)
            }
        }.value

        logger.info("Modelo exportado exitosamente como \(format.rawValue, privacy: .public)")
        return destination
    }
}
