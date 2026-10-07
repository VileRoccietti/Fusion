@preconcurrency import ARKit
import Foundation
import Observation
import SceneKit
import SwiftUI
import UIKit
import os

/// Real-time 3D depth point cloud color scheme like Heges
enum HegesColorPalette: String, CaseIterable, Identifiable, Sendable {
    case turbo = "Turbo / Calor"
    case viridis = "Viridis"
    case cyberpunk = "Cyber Neon"
    case normals = "Normales"
    case grayscale = "Métrico Gris"

    var id: String { rawValue }

    func colorForNormalizedDepth(_ t: Float) -> SCNVector4 {
        let clamped = max(0.0, min(1.0, t))
        switch self {
        case .turbo:
            // Rainbow thermal
            let r = sin(clamped * .pi)
            let g = sin((clamped + 0.33) * .pi)
            let b = cos(clamped * .pi * 0.5)
            return SCNVector4(r, g, b, 1.0)
        case .viridis:
            let r = 0.2 + 0.8 * clamped
            let g = 0.1 + 0.9 * sin(clamped * .pi)
            let b = 0.6 - 0.5 * clamped
            return SCNVector4(r, g, b, 1.0)
        case .cyberpunk:
            // Cyan to magenta
            return SCNVector4(clamped, 1.0 - clamped * 0.7, 1.0, 1.0)
        case .normals:
            return SCNVector4(0.5 + 0.5 * clamped, 0.7, 0.9, 1.0)
        case .grayscale:
            return SCNVector4(clamped, clamped, clamped, 1.0)
        }
    }
}

/// Camera sensor selection for Heges stream
enum HegesSensorSource: String, CaseIterable, Identifiable, Sendable {
    case backLiDAR = "LiDAR Trasero"
    case frontTrueDepth = "TrueDepth Frontal"

    var id: String { rawValue }
}

/// Real-time 3D depth streamer inspired by Heges
@MainActor
@Observable
final class HegesDepthEngine: NSObject, ARSessionDelegate {
    private static let logger = Logger(subsystem: "com.vileroccietti.Fusion", category: "heges")

    let arSession = ARSession()
    private(set) var isRunning = false
    private(set) var isFrozen = false

    // Sensor & Shading
    var sensorSource: HegesSensorSource = .backLiDAR {
        didSet { restartSession() }
    }
    var palette: HegesColorPalette = .turbo
    var minDepthMeters: Float = 0.20
    var maxDepthMeters: Float = 3.50

    // Live Metrics
    private(set) var livePointCount: Int = 0
    private(set) var currentFps: Double = 60.0
    private var lastFrameTime = Date()

    // Frozen snapshot points for export
    private(set) var frozenVertices: [SIMD3<Float>] = []
    private(set) var frozenColors: [SIMD3<Float>] = []

    override init() {
        super.init()
    }

    func start() {
        guard !isRunning else { return }
        restartSession()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        arSession.pause()
        isRunning = false
    }

    func toggleFreeze() {
        isFrozen.toggle()
        HapticFeedback.medium()
    }

    private func restartSession() {
        arSession.pause()
        arSession.delegate = self

        if sensorSource == .frontTrueDepth && ARFaceTrackingConfiguration.isSupported {
            let config = ARFaceTrackingConfiguration()
            arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
        } else {
            let config = ARWorldTrackingConfiguration()
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                config.sceneReconstruction = .mesh
            }
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                config.frameSemantics.insert(.sceneDepth)
            }
            arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
        }
    }

    // MARK: - ARSessionDelegate

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor [weak self] in
            self?.processFrame(frame)
        }
    }

    private func processFrame(_ frame: ARFrame) {
        let now = Date()
        let dt = now.timeIntervalSince(lastFrameTime)
        let fps = dt > 0 ? (1.0 / dt) : 60.0

        guard let depthData = frame.sceneDepth ?? frame.smoothedSceneDepth else {
            self.currentFps = fps
            self.lastFrameTime = now
            return
        }

        let depthMap = depthData.depthMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return }
        let floatPtr = base.assumingMemoryBound(to: Float32.self)

        // Subsample for smooth 60fps real-time 3D SceneKit rendering
        var extractedPoints: [SIMD3<Float>] = []
        var extractedColors: [SIMD3<Float>] = []
        let step = 4

        let intrinsics = frame.camera.intrinsics
        let fx = intrinsics[0][0]
        let fy = intrinsics[1][1]
        let cx = intrinsics[2][0]
        let cy = intrinsics[2][1]
        let camTransform = frame.camera.transform

        let minD = self.minDepthMeters
        let maxD = self.maxDepthMeters
        let currentPalette = self.palette

        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let d = floatPtr[y * width + x]
                if d >= minD && d <= maxD {
                    // Backproject to 3D camera space
                    let z = d
                    let xNorm = (Float(x) - cx) * z / fx
                    let yNorm = (Float(y) - cy) * z / fy
                    let localPos = SIMD4<Float>(xNorm, -yNorm, -z, 1.0)
                    let worldPos = camTransform * localPos

                    extractedPoints.append(SIMD3<Float>(worldPos.x, worldPos.y, worldPos.z))

                    // Normalize depth for palette
                    let norm = (d - minD) / max(0.01, (maxD - minD))
                    let col = currentPalette.colorForNormalizedDepth(norm)
                    extractedColors.append(SIMD3<Float>(col.x, col.y, col.z))
                }
            }
        }

        self.livePointCount = extractedPoints.count
        self.currentFps = fps * 0.2 + self.currentFps * 0.8
        self.lastFrameTime = now

        if !self.isFrozen {
            self.frozenVertices = extractedPoints
            self.frozenColors = extractedColors
        }
    }

    /// Export frozen frame to binary PLY
    func exportFrozenPointCloud() -> URL? {
        guard !frozenVertices.isEmpty else { return nil }
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("Heges_3D_\(Int(Date().timeIntervalSince1970)).ply")

        var header = ""
        header += "ply\n"
        header += "format ascii 1.0\n"
        header += "element vertex \(frozenVertices.count)\n"
        header += "property float x\n"
        header += "property float y\n"
        header += "property float z\n"
        header += "property uchar red\n"
        header += "property uchar green\n"
        header += "property uchar blue\n"
        header += "end_header\n"

        var data = Data(header.utf8)
        for i in 0..<frozenVertices.count {
            let v = frozenVertices[i]
            let c = frozenColors[i]
            let r = UInt8(max(0, min(255, c.x * 255)))
            let g = UInt8(max(0, min(255, c.y * 255)))
            let b = UInt8(max(0, min(255, c.z * 255)))
            let line = "\(v.x) \(v.y) \(v.z) \(r) \(g) \(b)\n"
            data.append(Data(line.utf8))
        }

        try? data.write(to: fileURL)
        return fileURL
    }
}
