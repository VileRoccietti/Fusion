import Foundation
import ModelIO
import SceneKit
import SceneKit.ModelIO
import os

/// Decimates and simplifies dense 3D polygonal meshes for real-time performance, web, or games
enum MeshDecimator {
    private static let logger = Logger(subsystem: "com.vileroccietti.Fusion", category: "decimator")

    enum DecimationLevel: Float, CaseIterable, Identifiable, Sendable {
        case original = 1.0
        case high = 0.75
        case medium = 0.50
        case low = 0.25
        case ultraLow = 0.10

        var id: Float { rawValue }

        var displayName: String {
            switch self {
            case .original: "Original (100%)"
            case .high: "Alta (75%)"
            case .medium: "Media (50%)"
            case .low: "Baja (25%)"
            case .ultraLow: "Ultra Ligera (10%)"
            }
        }
    }

    enum DecimateError: LocalizedError {
        case fileMissing
        case noMeshFound
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .fileMissing: "No se encontró el archivo del modelo."
            case .noMeshFound: "No se encontraron datos poligonales en el modelo."
            case .exportFailed(let detail): "Error al exportar el modelo optimizado: \(detail)"
            }
        }
    }

    /// Reduces polygon count to the specified ratio (e.g. 0.50 = 50% of triangles)
    static func decimate(
        modelURL: URL,
        ratio: Float,
        outputURL: URL
    ) async throws {
        guard FileManager.default.fileExists(atPath: modelURL.path(percentEncoded: false)) else {
            throw DecimateError.fileMissing
        }

        if ratio >= 0.99 {
            // No reduction needed, simply copy
            try? FileManager.default.removeItem(at: outputURL)
            try FileManager.default.copyItem(at: modelURL, to: outputURL)
            return
        }

        try await Task.detached(priority: .userInitiated) {
            let asset = MDLAsset(url: modelURL)
            guard asset.count > 0 else {
                throw DecimateError.noMeshFound
            }

            for index in 0..<asset.count {
                guard let mesh = asset.object(at: index) as? MDLMesh else { continue }
                guard let submeshes = mesh.submeshes as? [MDLSubmesh] else { continue }

                for submesh in submeshes {
                    let totalIndices = submesh.indexCount
                    let targetIndices = max(Int(Float(totalIndices) * ratio / 3.0) * 3, 3)

                    let step = max(Int(round(Float(totalIndices) / Float(targetIndices))), 1)

                    let indexBuffer = submesh.indexBuffer
                    let indexData = indexBuffer.map().bytes
                    var newIndices: [UInt32] = []
                    newIndices.reserveCapacity(targetIndices)

                    if submesh.indexType == .uInt16 {
                        for i in stride(from: 0, to: totalIndices - 2, by: 3 * step) {
                            let i0 = UInt32(indexData.load(fromByteOffset: i * 2, as: UInt16.self))
                            let i1 = UInt32(indexData.load(fromByteOffset: (i + 1) * 2, as: UInt16.self))
                            let i2 = UInt32(indexData.load(fromByteOffset: (i + 2) * 2, as: UInt16.self))
                            newIndices.append(contentsOf: [i0, i1, i2])
                        }
                    } else if submesh.indexType == .uInt32 {
                        for i in stride(from: 0, to: totalIndices - 2, by: 3 * step) {
                            let i0 = indexData.load(fromByteOffset: i * 4, as: UInt32.self)
                            let i1 = indexData.load(fromByteOffset: (i + 1) * 4, as: UInt32.self)
                            let i2 = indexData.load(fromByteOffset: (i + 2) * 4, as: UInt32.self)
                            newIndices.append(contentsOf: [i0, i1, i2])
                        }
                    }

                    if !newIndices.isEmpty {
                        let data = Data(bytes: newIndices, count: newIndices.count * MemoryLayout<UInt32>.size)
                        let allocator = MDLMeshBufferDataAllocator()
                        let newBuf = allocator.newBuffer(with: data, type: .index)
                        let simplifiedSubmesh = MDLSubmesh(
                            name: submesh.name,
                            indexBuffer: newBuf,
                            indexCount: newIndices.count,
                            indexType: .uInt32,
                            geometryType: .triangles,
                            material: submesh.material
                        )
                        mesh.submeshes = NSMutableArray(array: [simplifiedSubmesh])
                    }
                }
            }

            try? FileManager.default.removeItem(at: outputURL)
            do {
                try asset.export(to: outputURL)
                logger.info("Malla optimizada a ratio \(ratio, privacy: .public)")
            } catch {
                throw DecimateError.exportFailed(error.localizedDescription)
            }
        }.value
    }
}
