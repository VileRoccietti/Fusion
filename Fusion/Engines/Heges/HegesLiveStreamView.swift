@preconcurrency import SceneKit
import SwiftUI

/// Heges-style live 3D depth point cloud viewer with interactive orbit camera
struct HegesLiveStreamView: View {
    @State private var engine = HegesDepthEngine()
    @State private var exportedURL: URL?
    @State private var showShareSheet = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Real-time 3D SceneKit Point Cloud Viewport
            HegesViewportRepresentable(
                vertices: engine.frozenVertices,
                colors: engine.frozenColors
            )
            .ignoresSafeArea()

            // Heges HUD Overlays
            VStack {
                topStatsBar
                Spacer()
                depthRangeCard
                bottomToolbar
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            engine.start()
        }
        .onDisappear {
            engine.stop()
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Top Stats Bar

    private var topStatsBar: some View {
        HStack {
            // Live Sensor & FPS Badge
            HStack(spacing: 8) {
                Circle()
                    .fill(engine.isFrozen ? Color.blue : Color.green)
                    .frame(width: 8, height: 8)

                Text(engine.isFrozen ? "FOTOGRAMA CONGELADO" : "LIDAR EN VIVO")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.white)

                Text("•")
                    .foregroundStyle(.white.opacity(0.4))

                Text(String(format: "%.0f FPS", engine.currentFps))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.yellow)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            // Sensor Switcher (Back LiDAR / Front TrueDepth)
            Button {
                engine.sensorSource = (engine.sensorSource == .backLiDAR) ? .frontTrueDepth : .backLiDAR
                HapticFeedback.selection()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "camera.rotate")
                    Text(engine.sensorSource == .backLiDAR ? "LiDAR" : "TrueDepth")
                }
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(.white)
            }
        }
        .padding(.top, 44)
    }

    // MARK: - Depth Range Slider Card

    private var depthRangeCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text("FILTRO MÉTRICO DE PROFUNDIDAD")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(String(format: "%.2f m - %.2f m", engine.minDepthMeters, engine.maxDepthMeters))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.yellow)
            }

            HStack(spacing: 12) {
                Text("Min")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                Slider(value: $engine.minDepthMeters, in: 0.1...2.0, step: 0.05)
                    .tint(.yellow)
                Text("Max")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                Slider(value: $engine.maxDepthMeters, in: 1.0...5.0, step: 0.1)
                    .tint(.yellow)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Bottom Controls Bar

    private var bottomToolbar: some View {
        VStack(spacing: 14) {
            // Palettes Selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HegesColorPalette.allCases) { pal in
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                engine.palette = pal
                            }
                            HapticFeedback.selection()
                        } label: {
                            Text(pal.rawValue)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    engine.palette == pal ? Color.yellow : Color.black.opacity(0.5),
                                    in: Capsule()
                                )
                                .foregroundStyle(engine.palette == pal ? Color.black : Color.white)
                        }
                    }
                }
            }

            // Action Buttons
            HStack(spacing: 20) {
                // Freeze Button
                Button {
                    engine.toggleFreeze()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: engine.isFrozen ? "play.fill" : "pause.fill")
                        Text(engine.isFrozen ? "Reanudar" : "Congelar")
                    }
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(engine.isFrozen ? Color.blue : Color.white.opacity(0.15), in: Capsule())
                    .foregroundStyle(.white)
                }

                // Export PLY Button
                Button {
                    if let file = engine.exportFrozenPointCloud() {
                        self.exportedURL = file
                        self.showShareSheet = true
                        HapticFeedback.success()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Exportar 3D (.PLY)")
                    }
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.yellow, in: Capsule())
                    .foregroundStyle(.black)
                }
            }
        }
        .padding(.bottom, 20)
    }
}

// MARK: - SceneKit Point Cloud Viewport

private struct HegesViewportRepresentable: UIViewRepresentable {
    let vertices: [SIMD3<Float>]
    let colors: [SIMD3<Float>]

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        let scene = SCNScene()
        scnView.scene = scene
        scnView.backgroundColor = .black
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false

        // Camera
        let camNode = SCNNode()
        camNode.camera = SCNCamera()
        camNode.camera?.zNear = 0.01
        camNode.camera?.zFar = 20.0
        camNode.position = SCNVector3(0, 0, 1.2)
        scene.rootNode.addChildNode(camNode)

        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {
        guard let scene = scnView.scene else { return }

        // Remove old point cloud node
        scene.rootNode.childNode(withName: "PointCloudNode", recursively: false)?.removeFromParentNode()

        guard !vertices.isEmpty else { return }

        // Build SceneKit Point Geometry
        let vertexData = Data(bytes: vertices, count: vertices.count * MemoryLayout<SIMD3<Float>>.stride)
        let vertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: vertices.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )

        let colorData = Data(bytes: colors, count: colors.count * MemoryLayout<SIMD3<Float>>.stride)
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: colors.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )

        let indices: [Int32] = (0..<Int32(vertices.count)).map { $0 }
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.stride)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .point,
            primitiveCount: vertices.count,
            bytesPerIndex: MemoryLayout<Int32>.size
        )
        element.pointSize = 3.5
        element.minimumPointScreenSpaceRadius = 1.5
        element.maximumPointScreenSpaceRadius = 8.0

        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        geometry.materials = [material]

        let node = SCNNode(geometry: geometry)
        node.name = "PointCloudNode"
        scene.rootNode.addChildNode(node)
    }
}

// MARK: - Native Share Sheet Helper

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
