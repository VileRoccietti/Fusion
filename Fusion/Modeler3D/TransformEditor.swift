import Foundation
import ModelIO
import SceneKit
import SceneKit.ModelIO
import simd
import os

/// Applies metric transformations, centering, ground alignment, and axis rotations
enum TransformEditor {
    private static let logger = Logger(subsystem: "com.vile.ObjectScannerPro", category: "transform")

    enum Axis {
        case x, y, z
    }

    /// Transforms model geometry by baking rotation, centering, and scale into vertices
    static func applyTransform(
        modelURL: URL,
        outputURL: URL,
        rotateAxis: Axis? = nil,
        centerOrigin: Bool = false,
        snapToGround: Bool = false,
        scaleFactor: Float = 1.0
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            let asset = MDLAsset(url: modelURL)
            guard asset.count > 0 else { return }

            for index in 0..<asset.count {
                guard let mesh = asset.object(at: index) as? MDLMesh else { continue }
                guard let vertexBuffer = mesh.vertexBuffers.first else { continue }

                let vertexData = vertexBuffer.map().bytes
                let vertexCount = mesh.vertexCount
                let descriptor = mesh.vertexDescriptor
                guard let posAttr = descriptor.attributeNamed(MDLVertexAttributePosition) else { continue }
                let stride = descriptor.layouts[posAttr.bufferIndex].stride

                var minVec = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
                var maxVec = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)

                for v in 0..<vertexCount {
                    let offset = v * stride + posAttr.offset
                    let px = vertexData.load(fromByteOffset: offset, as: Float.self)
                    let py = vertexData.load(fromByteOffset: offset + 4, as: Float.self)
                    let pz = vertexData.load(fromByteOffset: offset + 8, as: Float.self)
                    let pos = SIMD3<Float>(px, py, pz)
                    minVec = simd_min(minVec, pos)
                    maxVec = simd_max(maxVec, pos)
                }

                let center = (minVec + maxVec) * 0.5
                let groundOffsetY = minVec.y

                for v in 0..<vertexCount {
                    let offset = v * stride + posAttr.offset
                    var px = vertexData.load(fromByteOffset: offset, as: Float.self)
                    var py = vertexData.load(fromByteOffset: offset + 4, as: Float.self)
                    var pz = vertexData.load(fromByteOffset: offset + 8, as: Float.self)

                    // Centering
                    if centerOrigin {
                        px -= center.x
                        pz -= center.z
                    }

                    // Snap bottom to ground Y=0
                    if snapToGround {
                        py -= groundOffsetY
                    }

                    // Rotate 90 degrees
                    if let rotateAxis {
                        switch rotateAxis {
                        case .y:
                            let nx = -pz
                            let nz = px
                            px = nx
                            pz = nz
                        case .x:
                            let ny = -pz
                            let nz = py
                            py = ny
                            pz = nz
                        case .z:
                            let nx = -py
                            let ny = px
                            px = nx
                            py = ny
                        }
                    }

                    // Scale
                    if scaleFactor != 1.0 {
                        px *= scaleFactor
                        py *= scaleFactor
                        pz *= scaleFactor
                    }

                    vertexData.storeBytes(of: px, toByteOffset: offset, as: Float.self)
                    vertexData.storeBytes(of: py, toByteOffset: offset + 4, as: Float.self)
                    vertexData.storeBytes(of: pz, toByteOffset: offset + 8, as: Float.self)
                }
            }

            try? FileManager.default.removeItem(at: outputURL)
            try asset.export(to: outputURL)
            logger.info("Transformación aplicada con éxito.")
        }.value
    }
}
