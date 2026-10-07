import Foundation
import os

/// Bundles captured high-resolution stills, depth maps, and poses into a ZIP archive
enum SourceImageBundle {
    private static let logger = Logger(subsystem: "com.vileroccietti.Fusion", category: "bundle")

    enum BundleError: LocalizedError {
        case imagesMissing
        case zipFailed(String)

        var errorDescription: String? {
            switch self {
            case .imagesMissing:
                "Las imágenes de origen fueron eliminadas o no se encontraron."
            case .zipFailed(let detail):
                "Error al comprimir el paquete ZIP: \(detail)"
            }
        }
    }

    /// Creates a ZIP archive containing all images ready to share or transfer to Mac
    static func makeArchive(imagesDirectory: URL, named baseName: String) async throws -> URL {
        let fileManager = FileManager.default
        let contents = (try? fileManager.contentsOfDirectory(atPath: imagesDirectory.path(percentEncoded: false))) ?? []
        guard !contents.isEmpty else { throw BundleError.imagesMissing }

        let safeName = baseName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let destination = fileManager.temporaryDirectory
            .appending(path: "\(safeName.isEmpty ? "scan" : safeName)-source-images.zip", directoryHint: .notDirectory)

        try await Task.detached(priority: .userInitiated) {
            try zip(directory: imagesDirectory, to: destination)
        }.value

        logger.info("Paquete ZIP generado: \(contents.count, privacy: .public) imágenes")
        return destination
    }

    private static func zip(directory: URL, to destination: URL) throws {
        var coordinationError: NSError?
        var copyError: Error?
        var didProduce = false

        NSFileCoordinator().coordinate(
            readingItemAt: directory,
            options: [.forUploading],
            error: &coordinationError
        ) { temporaryArchive in
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: temporaryArchive, to: destination)
                didProduce = true
            } catch {
                copyError = error
            }
        }

        if let coordinationError { throw BundleError.zipFailed(coordinationError.localizedDescription) }
        if let copyError { throw BundleError.zipFailed(copyError.localizedDescription) }
        guard didProduce else { throw BundleError.zipFailed("No se pudo generar el archivo ZIP.") }
    }

    static let macInstructions = """
    Para reconstruir con detalle máximo (.full o .raw) en una Mac:

    1. Descomprime las imágenes en tu carpeta de Descargas (~/Downloads/fotos).
    2. Compila la herramienta CLI incluida en Tools:
       swiftc -O -parse-as-library Tools/Reconstruct.swift -o /tmp/reconstruct
    3. Ejecuta la reconstrucción:
       /tmp/reconstruct ~/Downloads/fotos ~/Desktop/modelo_alta_res.usdz raw

    * En habitaciones, añade la bandera --room para desactivar el enmascarado de objetos.
    * En macOS, PhotogrammetrySession soporta los niveles .medium, .full y .raw, logrando hasta 15x más densidad de polígonos y mapas de desplazamiento de 8K.
    """
}
