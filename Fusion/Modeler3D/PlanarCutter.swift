import Foundation
import ModelIO
import SceneKit
import SceneKit.ModelIO
import simd
import os

/// Slices and discards unwanted floor, turntable, or table geometry beneath the scanned object
enum PlanarCutter {
    private static let logger = Logger(subsystem: "com.vileroccietti.Fusion", category: "cutter")

    enum CutterError: LocalizedError {
        case fileMissing
        case noGeometryFound
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .fileMissing: "No se encontró el archivo del modelo para recortar."
            case .noGeometryFound: "No se encontró malla geométrica modificable en el archivo."
            case .exportFailed(let detail): "Error al exportar el modelo recortado: \(detail)"
            }
        }
    }

    /// Clips all geometry where Y is below `cutoffY` in world coordinate space
    static func clipFloor(
        modelURL: URL,
        cutoffY: Float,
        outputURL: URL
    ) async throws {
        guard FileManager.default.fileExists(atPath: modelURL.path(percentEncoded: false)) else {
            throw CutterError.fileMissing
        }

        try await Task.detached(priority: .userInitiated) {
            let asset = MDLAsset(url: modelURL)
            guard asset.count > 0 else {
                throw CutterError.noGeometryFound
            }

            var modified = false

            for index in 0..<asset.count {
                guard let object = asset.object(at: index) as? MDLMesh else { continue }

                // Read vertex positions
                guard let vertexBuffer = object.vertexBuffers.first else { continue }
                let vertexData = vertexBuffer.map().bytes
                let vertexCount = object.vertexCount
                let vertexDescriptor = object.vertexDescriptor

                guard let posAttr = vertexDescriptor.attributeNamed(MDLVertexAttributePosition) else { continue }
                guard let layout = vertexDescriptor.layouts[posAttr.bufferIndex] as? MDLVertexBufferLayout else { continue }
                let stride = layout.stride

                // Mask vertices above cutoff
                var keepVertex = [Bool](repeating: true, count: vertexCount)
                for v in 0..<vertexCount {
                    let offset = v * stride + posAttr.offset
                    let y = vertexData.load(fromByteOffset: offset + MemoryLayout<Float>.size, as: Float.self)
                    if y < cutoffY {
                        keepVertex[v] = false
                        modified = true
                    }
                }

                // If submeshes exist, filter indices
                if let submeshes = object.submeshes as? [MDLSubmesh] {
                    for submesh in submeshes {
                        let indexBuffer = submesh.indexBuffer
                        let indexData = indexBuffer.map().bytes
                        let indexCount = submesh.indexCount

                        var filteredIndices: [UInt32] = []
                        filteredIndices.reserveCapacity(indexCount)

                        if submesh.indexType == .uInt16 {
                            for i in stride(from: 0, to: indexCount, by: 3) {
                                let i0 = UInt32(indexData.load(fromByteOffset: i * 2, as: UInt16.self))
                                let i1 = UInt32(indexData.load(fromByteOffset: (i + 1) * 2, as: UInt16.self))
                                let i2 = UInt32(indexData.load(fromByteOffset: (i + 2) * 2, as: UInt16.self))

                                if Int(i0) < vertexCount && Int(i1) < vertexCount && Int(i2) < vertexCount {
                                    if keepVertex[Int(i0)] && keepVertex[Int(i1)] && keepVertex[Int(i2)] {
                                        filteredIndices.append(contentsOf: [i0, i1, i2])
                                    }
                                }
                            }
                        } else if submesh.indexType == .uInt32 {
                            for i in stride(from: 0, to: indexCount, by: 3) {
                                let i0 = indexData.load(fromByteOffset: i * 4, as: UInt32.self)
                                let i1 = indexData.load(fromByteOffset: (i + 1) * 4, as: UInt32.self)
                                let i2 = indexData.load(fromByteOffset: (i + 2) * 4, as: UInt32.self)

                                if Int(i0) < vertexCount && Int(i1) < vertexCount && Int(i2) < vertexCount {
                                    if keepVertex[Int(i0)] && keepVertex[Int(i1)] && keepVertex[Int(i2)] {
                                        filteredIndices.append(contentsOf: [i0, i1, i2])
                                    }
                                }
                            }
                        }

                        if !filteredIndices.isEmpty && filteredIndices.count < indexCount {
                            let newIndexData = Data(bytes: filteredIndices, count: filteredIndices.count * MemoryLayout<UInt32>.size)
                            let allocator = MDLMeshBufferDataAllocator()
                            let newIndexBuffer = allocator.newBuffer(with: newIndexData, type: .index)

                            let newSubmesh = MDLSubmesh(
                                name: submesh.name,
                                indexBuffer: newIndexBuffer,
                                indexCount: filteredIndices.count,
                                indexType: .uInt32,
                                geometryType: .triangles,
                                material: submesh.material
                            )
                            object.submeshes = NSMutableArray(array: [newSubmesh])
                        }
                    }
                }
            }

            try? FileManager.default.removeItem(at: outputURL)
            do {
                try asset.export(to: outputURL)
                logger.info("Modelo recortado con éxito a \(outputURL.lastPathComponent, privacy: .public)")
            } catch {
                throw CutterError.exportFailed(error.localizedDescription)
            }
        }.value
    }
}
