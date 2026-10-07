import SceneKit
import SwiftUI
import ModelIO
import SceneKit.ModelIO
import simd

/// Interactive 3D Studio Viewport with PBR, wireframe, surface normals, clay matcap,
/// slicing plane indicator, and metric ground grid.
struct StudioViewport3D: UIViewRepresentable {
    let url: URL
    let renderMode: RenderMode
    var slicingPlaneHeight: Float? = nil
    var showSlicingPlane: Bool = false
    var showGroundGrid: Bool = true
    var onModelStats: (@MainActor (Int, Int, SIMD3<Int>) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView(frame: .zero)
        scnView.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0)
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.antialiasingMode = .multisampling4X
        scnView.preferredFramesPerSecond = 60

        context.coordinator.setupScene(in: scnView, url: url, onStats: onModelStats)
        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        if context.coordinator.currentURL != url {
            context.coordinator.setupScene(in: uiView, url: url, onStats: onModelStats)
        }

        context.coordinator.updateRenderMode(renderMode)
        context.coordinator.updateSlicingPlane(
            visible: showSlicingPlane,
            height: slicingPlaneHeight
        )
        context.coordinator.updateGrid(visible: showGroundGrid)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        var currentURL: URL
        var scene: SCNScene?
        var modelNode: SCNNode?
        var slicingNode: SCNNode?
        var gridNode: SCNNode?
        var originalMaterials: [SCNMaterial: (fillMode: SCNFillMode, lighting: SCNMaterial.LightingModel, contents: Any?)] = [:]
        var boundsMin = SCNVector3Zero
        var boundsMax = SCNVector3Zero

        init(url: URL) {
            self.currentURL = url
        }

        func setupScene(in scnView: SCNView, url: URL, onStats: (@MainActor (Int, Int, SIMD3<Int>) -> Void)?) {
            self.currentURL = url
            let scene = SCNScene()
            self.scene = scene
            self.originalMaterials.removeAll()

            // Load model using ModelIO / SceneKit
            let loadedScene: SCNScene?
            if url.pathExtension.lowercased() == "usdz" || url.pathExtension.lowercased() == "obj" {
                loadedScene = try? SCNScene(url: url, options: [.checkConsistency: false])
            } else {
                let asset = MDLAsset(url: url)
                loadedScene = SCNScene(mdlAsset: asset)
            }

            guard let root = loadedScene?.rootNode else {
                scnView.scene = scene
                return
            }

            let container = SCNNode()
            container.name = "ModelContainer"

            for child in root.childNodes {
                container.addChildNode(child)
            }
            scene.rootNode.addChildNode(container)
            self.modelNode = container

            // Calculate model bounding box and center
            var (minVec, maxVec) = container.boundingBox
            if minVec.x.isInfinite || minVec.x.isNaN {
                (minVec, maxVec) = (SCNVector3(-0.1, -0.1, -0.1), SCNVector3(0.1, 0.1, 0.1))
            }
            self.boundsMin = minVec
            self.boundsMax = maxVec

            let center = SCNVector3(
                (minVec.x + maxVec.x) / 2,
                (minVec.y + maxVec.y) / 2,
                (minVec.z + maxVec.z) / 2
            )
            let extent = max(
                max(maxVec.x - minVec.x, maxVec.y - minVec.y),
                maxVec.z - minVec.z
            )
            let safeExtent = max(extent, 0.05)

            // Center model at origin
            container.pivot = SCNMatrix4MakeTranslation(center.x, center.y, center.z)
            container.position = SCNVector3(0, (maxVec.y - minVec.y) / 2, 0)

            // Cache original materials
            container.enumerateHierarchy { node, _ in
                if let geometry = node.geometry {
                    for mat in geometry.materials {
                        if originalMaterials[mat] == nil {
                            originalMaterials[mat] = (mat.fillMode, mat.lightingModel, mat.diffuse.contents)
                        }
                    }
                }
            }

            // Create Ground Grid
            let grid = makeGroundGrid(size: CGFloat(safeExtent * 2.5))
            scene.rootNode.addChildNode(grid)
            self.gridNode = grid

            // Create Slicing Plane Indicator
            let slice = makeSlicingPlane(size: CGFloat(safeExtent * 2.0))
            slice.isHidden = true
            scene.rootNode.addChildNode(slice)
            self.slicingNode = slice

            // Lighting
            let ambient = SCNLight()
            ambient.type = .ambient
            ambient.color = UIColor(white: 0.45, alpha: 1.0)
            let ambientNode = SCNNode()
            ambientNode.light = ambient
            scene.rootNode.addChildNode(ambientNode)

            let directional = SCNLight()
            directional.type = .directional
            directional.color = UIColor(white: 0.85, alpha: 1.0)
            directional.castsShadow = true
            directional.shadowRadius = 8
            let dirNode = SCNNode()
            dirNode.light = directional
            dirNode.position = SCNVector3(safeExtent * 1.5, safeExtent * 3.0, safeExtent * 2.0)
            dirNode.look(at: SCNVector3(0, safeExtent * 0.5, 0))
            scene.rootNode.addChildNode(dirNode)

            // Camera
            let camera = SCNCamera()
            camera.zNear = 0.005
            camera.zFar = Double(max(safeExtent * 20, 10))
            camera.wantsHDR = true
            camera.exposureOffset = 0.2
            let cameraNode = SCNNode()
            cameraNode.camera = camera
            cameraNode.position = SCNVector3(safeExtent * 1.2, safeExtent * 1.4, safeExtent * 2.0)
            cameraNode.look(at: SCNVector3(0, safeExtent * 0.4, 0))
            scene.rootNode.addChildNode(cameraNode)

            scnView.scene = scene

            // Compute statistics
            var totalTris = 0
            var totalVerts = 0
            container.enumerateHierarchy { node, _ in
                if let geom = node.geometry {
                    for element in geom.elements {
                        totalTris += element.primitiveCount
                    }
                    if let source = geom.sources.first(where: { $0.semantic == .vertex }) {
                        totalVerts += source.vectorCount
                    }
                }
            }

            let widthMm = Int(round(abs(maxVec.x - minVec.x) * 1000))
            let heightMm = Int(round(abs(maxVec.y - minVec.y) * 1000))
            let depthMm = Int(round(abs(maxVec.z - minVec.z) * 1000))
            let bbox = SIMD3<Int>(widthMm, heightMm, depthMm)

            if let onStats {
                Task { @MainActor in
                    onStats(totalTris, totalVerts, bbox)
                }
            }
        }

        func updateRenderMode(_ mode: RenderMode) {
            guard let modelNode else { return }

            modelNode.enumerateHierarchy { node, _ in
                guard let geometry = node.geometry else { return }

                for material in geometry.materials {
                    let original = self.originalMaterials[material]

                    switch mode {
                    case .pbr:
                        material.fillMode = .fill
                        material.lightingModel = .physicallyBased
                        material.diffuse.contents = original?.contents
                        material.shaderModifiers = nil

                    case .wireframe:
                        material.fillMode = .lines
                        material.lightingModel = .constant
                        material.diffuse.contents = UIColor.systemGreen
                        material.shaderModifiers = nil

                    case .normals:
                        material.fillMode = .fill
                        material.lightingModel = .constant
                        material.shaderModifiers = [
                            .surface: """
                            vec3 n = normalize(_surface.normal);
                            _surface.diffuse = vec4(n * 0.5 + 0.5, 1.0);
                            """
                        ]

                    case .pointCloud:
                        material.fillMode = .fill
                        material.lightingModel = .constant
                        material.diffuse.contents = UIColor.cyan
                        material.shaderModifiers = nil

                    case .clay:
                        material.fillMode = .fill
                        material.lightingModel = .physicallyBased
                        material.diffuse.contents = UIColor(red: 0.78, green: 0.74, blue: 0.70, alpha: 1.0)
                        material.roughness.contents = 0.75
                        material.metalness.contents = 0.05
                        material.shaderModifiers = nil

                    case .unlit:
                        material.fillMode = .fill
                        material.lightingModel = .constant
                        material.diffuse.contents = original?.contents
                        material.shaderModifiers = nil
                    }
                }
            }
        }

        func updateSlicingPlane(visible: Bool, height: Float?) {
            guard let slicingNode else { return }
            slicingNode.isHidden = !visible
            if let height {
                slicingNode.position.y = height
            }
        }

        func updateGrid(visible: Bool) {
            gridNode?.isHidden = !visible
        }

        private func makeGroundGrid(size: CGFloat) -> SCNNode {
            let plane = SCNPlane(width: size, height: size)
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = makeGridImage()
            material.isDoubleSided = true
            material.diffuse.wrapS = .repeat
            material.diffuse.wrapT = .repeat
            material.diffuse.contentsTransform = SCNMatrix4MakeScale(20, 20, 1)
            plane.materials = [material]

            let node = SCNNode(geometry: plane)
            node.eulerAngles.x = -.pi / 2
            node.position = SCNVector3(0, 0, 0)
            node.opacity = 0.45
            return node
        }

        private func makeSlicingPlane(size: CGFloat) -> SCNNode {
            let plane = SCNPlane(width: size, height: size)
            let mat = SCNMaterial()
            mat.lightingModel = .constant
            mat.diffuse.contents = UIColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.4)
            mat.isDoubleSided = true
            plane.materials = [mat]

            let node = SCNNode(geometry: plane)
            node.eulerAngles.x = -.pi / 2
            return node
        }

        private func makeGridImage() -> UIImage {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
            return renderer.image { ctx in
                ctx.cgContext.setStrokeColor(UIColor(white: 0.35, alpha: 0.5).cgColor)
                ctx.cgContext.setLineWidth(1.0)
                ctx.cgContext.stroke(CGRect(x: 0, y: 0, width: 64, height: 64))
            }
        }
    }
}
