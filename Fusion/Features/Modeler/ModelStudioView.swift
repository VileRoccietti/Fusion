import SwiftUI

/// Full-featured 3D Modeler & AR Studio
struct ModelStudioView: View {
    let record: ScanRecord
    @Environment(ScanStorage.self) private var storage
    @Environment(\.dismiss) private var dismiss

    // Viewport State
    @State private var renderMode: RenderMode = .pbr
    @State private var showGrid = true
    @State private var triangleCount: Int = 0
    @State private var vertexCount: Int = 0
    @State private var bboxMm: SIMD3<Int> = .zero

    // Modeler Tools
    @State private var activeTool: StudioTool? = nil
    @State private var slicingHeight: Float = 0.0
    @State private var showSlicingPlane = false
    @State private var selectedDecimation: MeshDecimator.DecimationLevel = .medium
    @State private var isProcessingTool = false
    @State private var statusMessage: String?
    @State private var showARStudio = false

    // Export Sheet
    @State private var isExporting = false
    @State private var exportFormat: MeshExportFormat = .usdz
    @State private var shareableURL: URL?
    @State private var showShareSheet = false

    enum StudioTool: String, CaseIterable, Identifiable {
        case planarCut = "Cortar Base"
        case decimate = "Simplificar"
        case transform = "Transformar"
        case ar = "Espacio AR"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .planarCut: "scissors"
            case .decimate: "arrow.triangle.merge"
            case .transform: "arrow.up.and.down.and.arrow.left.and.right"
            case .ar: "arkit"
            }
        }
    }

    private var currentModelURL: URL {
        storage.modelURL(for: record)
    }

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()

            // 3D Viewport
            StudioViewport3D(
                url: currentModelURL,
                renderMode: renderMode,
                slicingPlaneHeight: slicingHeight,
                showSlicingPlane: showSlicingPlane,
                showGroundGrid: showGrid,
                onModelStats: { tris, verts, bbox in
                    self.triangleCount = tris
                    self.vertexCount = verts
                    self.bboxMm = bbox
                    if record.triangleCount == nil || record.triangleCount != tris {
                        var updated = record
                        updated.triangleCount = tris
                        updated.vertexCount = verts
                        updated.dimensionsMillimetres = [Int(bbox.x), Int(bbox.y), Int(bbox.z)]
                        storage.updateRecord(updated)
                    }
                }
            )
            .ignoresSafeArea()

            // UI Overlays
            VStack(spacing: 0) {
                topBar
                Spacer()
                if let activeTool {
                    toolPanel(for: activeTool)
                }
                bottomToolbar
            }

            if isProcessingTool {
                Color.black.opacity(0.6).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView()
                        .scaleEffect(1.4)
                        .tint(.yellow)
                    Text("Procesando geometría 3D...")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(28)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showARStudio) {
            ARImmersiveScanView(modelURL: currentModelURL, scanName: record.name)
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareableURL {
                ShareLink(item: shareableURL)
                    .presentationDetents([.medium])
            }
        }
        .alert(statusMessage ?? "", isPresented: Binding(get: { statusMessage != nil }, set: { if !$0 { statusMessage = nil } })) {
            Button("OK") { statusMessage = nil }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.6), in: Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(record.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(record.engine.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 6)

            Spacer()

            // Model Stats Badge
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(triangleCount.formatted()) tris · \(vertexCount.formatted()) verts")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.yellow)
                if bboxMm != .zero {
                    Text("\(bboxMm.x) × \(bboxMm.y) × \(bboxMm.z) mm")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))

            // Export Button
            Menu {
                ForEach(MeshExportFormat.allCases) { format in
                    Button {
                        exportAs(format)
                    } label: {
                        Label(format.displayName, systemImage: "square.and.arrow.up")
                    }
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.6), in: Circle())
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Tool Panel

    @ViewBuilder
    private func toolPanel(for tool: StudioTool) -> some View {
        VStack(spacing: 12) {
            HStack {
                Label(tool.rawValue, systemImage: tool.icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.yellow)
                Spacer()
                Button {
                    activeTool = nil
                    showSlicingPlane = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            switch tool {
            case .planarCut:
                VStack(spacing: 8) {
                    Text("Ajusta la altura del plano de corte para eliminar la mesa o el suelo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("Corte Y:")
                            .font(.caption.monospacedDigit())
                        Slider(value: $slicingHeight, in: -0.2...0.2)
                            .tint(.red)
                        Text(String(format: "%.1f cm", slicingHeight * 100))
                            .font(.caption.monospacedDigit().weight(.bold))
                            .frame(width: 55)
                    }

                    Button {
                        applyPlanarCut()
                    } label: {
                        HStack {
                            Image(systemName: "scissors")
                            Text("Recortar Base (Cortar Geometría)")
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.yellow, in: Capsule())
                    }
                }

            case .decimate:
                VStack(spacing: 8) {
                    Text("Reduce la densidad de triángulos para exportación rápida o juegos.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Nivel", selection: $selectedDecimation) {
                        ForEach(MeshDecimator.DecimationLevel.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button {
                        applyDecimation()
                    } label: {
                        HStack {
                            Image(systemName: "bolt.fill")
                            Text("Aplicar Reducción")
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.yellow, in: Capsule())
                    }
                }

            case .transform:
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Button("Ajustar al Suelo") {
                            applyTransform(snapToGround: true)
                        }
                        .buttonStyle(ToolButtonStyle())

                        Button("Centrar Origen") {
                            applyTransform(centerOrigin: true)
                        }
                        .buttonStyle(ToolButtonStyle())
                    }

                    HStack(spacing: 8) {
                        Button("Girar 90° Y") {
                            applyTransform(rotateAxis: .y)
                        }
                        .buttonStyle(ToolButtonStyle())

                        Button("Girar 90° X") {
                            applyTransform(rotateAxis: .x)
                        }
                        .buttonStyle(ToolButtonStyle())
                    }
                }

            case .ar:
                EmptyView()
            }
        }
        .padding(14)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        VStack(spacing: 10) {
            // Render Mode Selector Scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(RenderMode.allCases) { mode in
                        Button {
                            renderMode = mode
                            HapticFeedback.selection()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: mode.iconName)
                                Text(mode.displayName)
                            }
                            .font(.caption.weight(renderMode == mode ? .bold : .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(renderMode == mode ? Color.yellow : Color.white.opacity(0.12), in: Capsule())
                            .foregroundStyle(renderMode == mode ? Color.black : Color.white)
                        }
                    }
                }
                .padding(.horizontal)
            }

            // Studio Tool Buttons
            HStack(spacing: 10) {
                ForEach(StudioTool.allCases) { tool in
                    Button {
                        if tool == .ar {
                            showARStudio = true
                            HapticFeedback.medium()
                        } else {
                            if activeTool == tool {
                                activeTool = nil
                                showSlicingPlane = false
                            } else {
                                activeTool = tool
                                showSlicingPlane = (tool == .planarCut)
                            }
                            HapticFeedback.selection()
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tool.icon)
                                .font(.system(size: 18))
                            Text(tool.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(activeTool == tool ? Color.yellow.opacity(0.2) : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(activeTool == tool ? Color.yellow : Color.clear, lineWidth: 1.5))
                        .foregroundStyle(activeTool == tool ? Color.yellow : Color.white)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 10)
        .background(.black.opacity(0.8))
    }

    // MARK: - Actions

    private func applyPlanarCut() {
        isProcessingTool = true
        HapticFeedback.heavy()
        let destination = storage.directoryURL(for: record).appending(path: "model_clipped.usdz")

        Task {
            do {
                try await PlanarCutter.clipFloor(
                    modelURL: currentModelURL,
                    cutoffY: slicingHeight,
                    outputURL: destination
                )
                try? FileManager.default.removeItem(at: currentModelURL)
                try FileManager.default.moveItem(at: destination, to: currentModelURL)

                var updated = record
                updated.isEdited = true
                storage.updateRecord(updated)

                isProcessingTool = false
                showSlicingPlane = false
                activeTool = nil
                statusMessage = "Base recortada con éxito."
                HapticFeedback.success()
            } catch {
                isProcessingTool = false
                statusMessage = "Error al recortar: \(error.localizedDescription)"
                HapticFeedback.error()
            }
        }
    }

    private func applyDecimation() {
        isProcessingTool = true
        HapticFeedback.heavy()
        let destination = storage.directoryURL(for: record).appending(path: "model_decimated.usdz")

        Task {
            do {
                try await MeshDecimator.decimate(
                    modelURL: currentModelURL,
                    ratio: selectedDecimation.rawValue,
                    outputURL: destination
                )
                try? FileManager.default.removeItem(at: currentModelURL)
                try FileManager.default.moveItem(at: destination, to: currentModelURL)

                var updated = record
                updated.isEdited = true
                storage.updateRecord(updated)

                isProcessingTool = false
                activeTool = nil
                statusMessage = "Malla optimizada a \(selectedDecimation.displayName)."
                HapticFeedback.success()
            } catch {
                isProcessingTool = false
                statusMessage = "Error al simplificar: \(error.localizedDescription)"
                HapticFeedback.error()
            }
        }
    }

    private func applyTransform(
        rotateAxis: TransformEditor.Axis? = nil,
        centerOrigin: Bool = false,
        snapToGround: Bool = false
    ) {
        isProcessingTool = true
        HapticFeedback.medium()
        let destination = storage.directoryURL(for: record).appending(path: "model_transformed.usdz")

        Task {
            do {
                try await TransformEditor.applyTransform(
                    modelURL: currentModelURL,
                    outputURL: destination,
                    rotateAxis: rotateAxis,
                    centerOrigin: centerOrigin,
                    snapToGround: snapToGround
                )
                try? FileManager.default.removeItem(at: currentModelURL)
                try FileManager.default.moveItem(at: destination, to: currentModelURL)

                var updated = record
                updated.isEdited = true
                storage.updateRecord(updated)

                isProcessingTool = false
                statusMessage = "Transformación aplicada."
                HapticFeedback.success()
            } catch {
                isProcessingTool = false
                statusMessage = "Error: \(error.localizedDescription)"
                HapticFeedback.error()
            }
        }
    }

    private func exportAs(_ format: MeshExportFormat) {
        isExporting = true
        HapticFeedback.medium()

        Task {
            do {
                let url = try await MeshExporter.export(
                    modelAt: currentModelURL,
                    as: format,
                    namedLike: record.name
                )
                self.shareableURL = url
                self.showShareSheet = true
                self.isExporting = false
                HapticFeedback.success()
            } catch {
                self.isExporting = false
                self.statusMessage = "Error al exportar: \(error.localizedDescription)"
                HapticFeedback.error()
            }
        }
    }
}

private struct ToolButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(.white.opacity(configuration.isPressed ? 0.25 : 0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}
