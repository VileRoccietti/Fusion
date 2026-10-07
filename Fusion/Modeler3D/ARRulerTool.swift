import Foundation
import RealityKit
import ARKit
import SwiftUI
import simd

/// AR Measurement data representation
struct ARMeasurement: Identifiable, Equatable {
    let id = UUID()
    let startPoint: SIMD3<Float>
    let endPoint: SIMD3<Float>
    let distanceMeters: Float

    var millimeters: Int {
        Int(round(distanceMeters * 1000))
    }

    var centimetersFormatted: String {
        String(format: "%.1f cm", distanceMeters * 100)
    }

    var inchesFormatted: String {
        String(format: "%.2f in", distanceMeters * 39.3701)
    }
}

/// AR Laser Ruler Tool: Measures real-world distances between tapped points with 3D laser lines
@MainActor
final class ARRulerTool: ObservableObject {
    @Published var measurements: [ARMeasurement] = []
    @Published var activeStartPoint: SIMD3<Float>? = nil
    @Published var isMeasuring = false

    private var activeAnchor: AnchorEntity?

    func addPoint(_ point: SIMD3<Float>, in arView: ARView) {
        if let start = activeStartPoint {
            // Completed a measurement line
            let dist = simd_distance(start, point)
            let measurement = ARMeasurement(startPoint: start, endPoint: point, distanceMeters: dist)
            measurements.append(measurement)
            activeStartPoint = nil

            renderMeasurementLine(measurement, in: arView)
            HapticFeedback.success()
        } else {
            // First point
            activeStartPoint = point
            renderStartMarker(at: point, in: arView)
            HapticFeedback.light()
        }
    }

    func clearMeasurements(in arView: ARView) {
        measurements.removeAll()
        activeStartPoint = nil
        if let anchor = activeAnchor {
            arView.scene.removeAnchor(anchor)
            activeAnchor = nil
        }
        HapticFeedback.medium()
    }

    private func getOrCreateAnchor(in arView: ARView) -> AnchorEntity {
        if let existing = activeAnchor { return existing }
        let anchor = AnchorEntity(world: .zero)
        arView.scene.addAnchor(anchor)
        self.activeAnchor = anchor
        return anchor
    }

    private func renderStartMarker(at point: SIMD3<Float>, in arView: ARView) {
        let anchor = getOrCreateAnchor(in: arView)
        let mesh = MeshResource.generateSphere(radius: 0.008)
        let mat = SimpleMaterial(color: .systemCyan, isMetallic: false)
        let sphere = ModelEntity(mesh: mesh, materials: [mat])
        sphere.position = point
        anchor.addChild(sphere)
    }

    private func renderMeasurementLine(_ measurement: ARMeasurement, in arView: ARView) {
        let anchor = getOrCreateAnchor(in: arView)

        // End sphere
        let sphereMesh = MeshResource.generateSphere(radius: 0.008)
        let sphereMat = SimpleMaterial(color: .systemYellow, isMetallic: false)
        let sphere = ModelEntity(mesh: sphereMesh, materials: [sphereMat])
        sphere.position = measurement.endPoint
        anchor.addChild(sphere)

        // Laser line (cylinder)
        let length = measurement.distanceMeters
        let lineMesh = MeshResource.generateBox(width: 0.004, height: length, depth: 0.004, cornerRadius: 0.002)
        let lineMat = UnlitMaterial(color: .systemYellow)
        let line = ModelEntity(mesh: lineMesh, materials: [lineMat])

        let midpoint = (measurement.startPoint + measurement.endPoint) * 0.5
        line.position = midpoint

        // Orient cylinder between start and end
        let direction = normalize(measurement.endPoint - measurement.startPoint)
        let up = SIMD3<Float>(0, 1, 0)
        let rot = simd_quatf(from: up, to: direction)
        line.orientation = rot
        anchor.addChild(line)

        // 3D Text Tag
        let textMesh = MeshResource.generateText(
            "\(measurement.centimetersFormatted) (\(measurement.millimeters) mm)",
            extrusionDepth: 0.002,
            font: .systemFont(ofSize: 0.03, weight: .bold),
            containerFrame: .zero,
            alignment: .center
        )
        let textMat = UnlitMaterial(color: .white)
        let textEntity = ModelEntity(mesh: textMesh, materials: [textMat])
        textEntity.position = midpoint + SIMD3<Float>(0, 0.03, 0)
        anchor.addChild(textEntity)
    }
}
