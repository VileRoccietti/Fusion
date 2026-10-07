@preconcurrency import ARKit
import Foundation
import Observation
import RealityKit
import SwiftUI
import UIKit
import os

/// Phosphor night vision tube display modes
enum NightVisionMode: String, CaseIterable, Identifiable, Sendable {
    case greenPhosphor = "Fósforo Verde"
    case whitePhosphor = "Fósforo Blanco"
    case flirThermal = "Térmico FLIR"

    var id: String { rawValue }

    var tintColor: Color {
        switch self {
        case .greenPhosphor: Color(red: 0.1, green: 1.0, blue: 0.3)
        case .whitePhosphor: Color(red: 0.85, green: 0.95, blue: 1.0)
        case .flirThermal: Color(red: 1.0, green: 0.4, blue: 0.1)
        }
    }

    var militaryCode: String {
        switch self {
        case .greenPhosphor: "GEN-3 NVG (PVS-14)"
        case .whitePhosphor: "W-PHOSPHOR (GPNVG)"
        case .flirThermal: "FLIR IR-HEAT"
        }
    }
}

/// LiDAR Time-of-Flight night vision engine for total darkness navigation
@MainActor
@Observable
final class LiDARNightVisionEngine: NSObject, ARSessionDelegate {
    private static let logger = Logger(subsystem: "com.vileroccietti.Fusion", category: "nightvision")

    let arSession = ARSession()
    private(set) var isRunning = false

    // Night Vision Configuration
    var mode: NightVisionMode = .greenPhosphor
    var gainMultiplier: Float = 1.8
    var isIRIlluminatorOn = false

    // Tactical Rangefinder (LiDAR center measurement)
    private(set) var targetDistanceMeters: Float = 0.0
    private(set) var targetDistanceText: String = "--- m"
    private(set) var proximityWarning: Bool = false
    private(set) var compassHeading: Double = 0.0

    // Capture
    private(set) var lastCapturedSnapshot: UIImage?

    override init() {
        super.init()
    }

    func start() {
        guard !isRunning else { return }
        let configuration = ARWorldTrackingConfiguration()

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }

        arSession.delegate = self
        arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
        HapticFeedback.light()
    }

    func stop() {
        guard isRunning else { return }
        arSession.pause()
        isRunning = false
    }

    func toggleTorch() {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if device.torchMode == .on {
                device.torchMode = .off
                isIRIlluminatorOn = false
            } else {
                try device.setTorchModeOn(level: 1.0)
                isIRIlluminatorOn = true
            }
            device.unlockForConfiguration()
            HapticFeedback.selection()
        } catch {
            Self.logger.error("No se pudo alternar linterna: \(error.localizedDescription)")
        }
    }

    // MARK: - ARSessionDelegate

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Calculate center laser rangefinder distance via LiDAR depth map or raycast
        let centerPoint = CGPoint(x: 0.5, y: 0.5)
        let results = frame.raycastQuery(from: centerPoint, allowing: .estimatedPlane, alignment: .any)
        let distance: Float

        if let hit = session.raycast(results).first {
            let camPos = frame.camera.transform.columns.3
            let hitPos = hit.worldTransform.columns.3
            let dx = camPos.x - hitPos.x
            let dy = camPos.y - hitPos.y
            let dz = camPos.z - hitPos.z
            distance = sqrt(dx*dx + dy*dy + dz*dz)
        } else if let depthMap = frame.sceneDepth?.depthMap {
            // Read center pixel from LiDAR depth map
            CVPixelBufferLockBaseAddress(depthMap, .readOnly)
            let width = CVPixelBufferGetWidth(depthMap)
            let height = CVPixelBufferGetHeight(depthMap)
            let baseAddress = CVPixelBufferGetBaseAddress(depthMap)
            let floatBuffer = baseAddress?.assumingMemoryBound(to: Float32.self)
            let centerIndex = (height / 2) * width + (width / 2)
            let depthVal = floatBuffer?[centerIndex] ?? 0.0
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            distance = depthVal > 0.05 ? depthVal : 0.0
        } else {
            distance = 0.0
        }

        let heading = Double(frame.camera.eulerAngles.y * (180.0 / .pi))

        Task { @MainActor in
            self.targetDistanceMeters = distance
            if distance > 0.05 && distance < 20.0 {
                self.targetDistanceText = String(format: "%.2f m", distance)
                self.proximityWarning = distance < 1.0

                if self.proximityWarning {
                    HapticFeedback.light()
                }
            } else {
                self.targetDistanceText = "FUERA DE ALCANCE"
                self.proximityWarning = false
            }

            self.compassHeading = heading >= 0 ? heading : heading + 360.0
        }
    }
}
