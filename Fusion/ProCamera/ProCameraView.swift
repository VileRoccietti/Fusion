@preconcurrency import AVFoundation
import SwiftUI

/// Top-level camera operational modes
enum CameraHubMode: String, CaseIterable, Identifiable, Sendable {
    case photo = "FOTO"
    case video = "VIDEO"
    case nightVision = "NOCTURNO"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .photo: "camera.fill"
        case .video: "video.fill"
        case .nightVision: "moon.stars.fill"
        }
    }
}

/// Camera mode selector row mimicking native iOS camera ergonomics
struct CameraModeSelectorRow: View {
    @Binding var currentMode: CameraHubMode

    var body: some View {
        HStack(spacing: 20) {
            ForEach(CameraHubMode.allCases) { mode in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        currentMode = mode
                    }
                    HapticFeedback.selection()
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 13, weight: currentMode == mode ? .black : .bold, design: .rounded))
                        .foregroundStyle(currentMode == mode ? Color.yellow : Color.white.opacity(0.6))
                        .scaleEffect(currentMode == mode ? 1.08 : 0.95)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                }
            }
        }
    }
}

/// Master Hub Camera View with seamless switching between 48MP ProRAW, 4K/120 Cine Video, and LiDAR Night Vision
struct ProCameraView: View {
    @State private var currentMode: CameraHubMode = .photo

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch currentMode {
            case .photo:
                PhotoCameraStudioView(currentMode: $currentMode)
            case .video:
                ProVideoView(currentMode: $currentMode)
            case .nightVision:
                LiDARNightVisionView(currentMode: $currentMode)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - 48MP ProRAW Photo Studio View

struct PhotoCameraStudioView: View {
    @Binding var currentMode: CameraHubMode
    @State private var engine = ProCameraEngine()
    @StateObject private var horizonGuide = HorizonLevelGuide()

    @State private var selectedControl: ManualControlTab = .exposure
    @State private var showGrid = true
    @State private var showZoomWheel = false

    enum ManualControlTab: String, CaseIterable, Identifiable {
        case exposure = "EXP"
        case focus = "ENFOQUE"
        case wb = "WB"
        case ev = "EV"

        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Viewfinder
            CameraPreviewView(session: engine.session)
                .ignoresSafeArea()

            // Overlays
            if showGrid {
                CompositionGridView()
                    .allowsHitTesting(false)
            }

            if engine.isHistogramEnabled {
                VStack {
                    HStack {
                        Spacer()
                        LiveHistogramView(bins: engine.histogramBins)
                            .padding(.top, 56)
                            .padding(.trailing, 16)
                    }
                    Spacer()
                }
            }

            HorizonLevelOverlay(guide: horizonGuide)

            // UI Chrome
            VStack(spacing: 0) {
                topToolbar
                Spacer()

                if showZoomWheel {
                    ZoomWheelControl(zoomFactor: Binding(
                        get: { engine.activeLens.zoomFactor },
                        set: { _ in }
                    ))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                manualControlsBar
                bottomBar
            }
        }
        .onAppear {
            engine.configure()
            engine.start()
            horizonGuide.start()
        }
        .onDisappear {
            engine.stop()
            horizonGuide.stop()
        }
    }

    // MARK: - Top Toolbar

    private var topToolbar: some View {
        HStack(spacing: 12) {
            Button {
                engine.isProRAWEnabled.toggle()
                HapticFeedback.light()
            } label: {
                Text(engine.isProRAWEnabled ? "ProRAW 48MP" : "HEIF MAX")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(engine.isProRAWEnabled ? Color.yellow : Color.black.opacity(0.5), in: Capsule())
                    .foregroundStyle(engine.isProRAWEnabled ? Color.black : Color.white)
            }

            Spacer()

            Button {
                showGrid.toggle()
                HapticFeedback.light()
            } label: {
                Image(systemName: showGrid ? "grid" : "grid.slash")
                    .font(.subheadline)
                    .foregroundStyle(showGrid ? .yellow : .white)
                    .frame(width: 32, height: 32)
                    .background(.black.opacity(0.5), in: Circle())
            }

            Button {
                engine.isFocusPeakingEnabled.toggle()
                HapticFeedback.light()
            } label: {
                Image(systemName: "camera.metering.spot")
                    .font(.subheadline)
                    .foregroundStyle(engine.isFocusPeakingEnabled ? .green : .white)
                    .frame(width: 32, height: 32)
                    .background(.black.opacity(0.5), in: Circle())
            }

            Button {
                engine.isHistogramEnabled.toggle()
                HapticFeedback.light()
            } label: {
                Image(systemName: "chart.bar.xaxis")
                    .font(.subheadline)
                    .foregroundStyle(engine.isHistogramEnabled ? .yellow : .white)
                    .frame(width: 32, height: 32)
                    .background(.black.opacity(0.5), in: Circle())
            }

            Button {
                engine.resetToAuto()
            } label: {
                Text("AUTO")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(!engine.isManualExposure && !engine.isManualFocus ? Color.green : Color.black.opacity(0.5), in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal)
        .padding(.top, 48)
    }

    // MARK: - Manual Controls Bar

    private var manualControlsBar: some View {
        VStack(spacing: 8) {
            switch selectedControl {
            case .exposure:
                HStack {
                    Text("ISO \(Int(engine.currentISO))")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .frame(width: 70)
                    Slider(value: Binding(get: { engine.currentISO }, set: { engine.setManualExposure(shutter: engine.currentShutter, iso: $0) }), in: engine.minISO...engine.maxISO)
                        .tint(.yellow)
                }
                .padding(.horizontal)

            case .focus:
                HStack {
                    Text("MF \(String(format: "%.2f", engine.currentFocus))")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .frame(width: 70)
                    Slider(value: Binding(get: { engine.currentFocus }, set: { engine.setManualFocus($0) }), in: 0.0...1.0)
                        .tint(.green)
                }
                .padding(.horizontal)

            case .wb:
                HStack {
                    Text("\(engine.currentKelvin) K")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .frame(width: 70)
                    Slider(value: Binding(get: { Double(engine.currentKelvin) }, set: { engine.setManualKelvin(Int($0)) }), in: 2500...9000, step: 100)
                        .tint(.orange)
                }
                .padding(.horizontal)

            case .ev:
                HStack {
                    Text(String(format: "%+.1f EV", engine.exposureBias))
                        .font(.caption.monospacedDigit().weight(.bold))
                        .frame(width: 70)
                    Slider(value: Binding(get: { engine.exposureBias }, set: { engine.setExposureBias($0) }), in: -3.0...3.0, step: 0.3)
                        .tint(.yellow)
                }
                .padding(.horizontal)
            }

            HStack(spacing: 6) {
                ForEach(ManualControlTab.allCases) { tab in
                    Button {
                        selectedControl = tab
                        HapticFeedback.selection()
                    } label: {
                        Text(tab.rawValue)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(selectedControl == tab ? Color.yellow : Color.white.opacity(0.12), in: Capsule())
                            .foregroundStyle(selectedControl == tab ? Color.black : Color.white)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            // Lens Picker
            HStack(spacing: 12) {
                ForEach(ProLens.allCases) { lens in
                    Button {
                        engine.switchLens(lens)
                    } label: {
                        Text(lens.label)
                            .font(.system(size: 12, weight: engine.activeLens == lens ? .black : .bold))
                            .frame(width: 38, height: 38)
                            .background(engine.activeLens == lens ? Color.yellow : Color.black.opacity(0.55), in: Circle())
                            .foregroundStyle(engine.activeLens == lens ? Color.black : Color.white)
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.8))
                    }
                }
            }

            // Mode Selector Row (FOTO | VIDEO | NOCTURNO)
            CameraModeSelectorRow(currentMode: $currentMode)
                .padding(.top, 2)

            // Shutter Button Row
            HStack {
                // Last Photo Thumbnail
                if let thumb = engine.lastCapturedImage {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.3), lineWidth: 1))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 48, height: 48)
                }

                Spacer()

                // Tactile Shutter Button
                Button {
                    engine.capturePhoto()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 3.5)
                            .frame(width: 72, height: 72)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 60, height: 60)
                    }
                }
                .disabled(engine.isCapturing)

                Spacer()

                // Zoom Wheel toggle button
                Button {
                    withAnimation(.spring(response: 0.25)) {
                        showZoomWheel.toggle()
                    }
                    HapticFeedback.selection()
                } label: {
                    Image(systemName: "dial.low.fill")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 48, height: 48)
                        .background(showZoomWheel ? Color.yellow : Color.black.opacity(0.6), in: Circle())
                        .foregroundStyle(showZoomWheel ? Color.black : Color.white)
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
            }
            .padding(.horizontal, 30)
        }
        .padding(.bottom, 12)
        .background(.black.opacity(0.85))
    }
}

// MARK: - Composition Grid

private struct CompositionGridView: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            Path { path in
                path.move(to: CGPoint(x: w / 3, y: 0))
                path.addLine(to: CGPoint(x: w / 3, y: h))
                path.move(to: CGPoint(x: 2 * w / 3, y: 0))
                path.addLine(to: CGPoint(x: 2 * w / 3, y: h))

                path.move(to: CGPoint(x: 0, y: h / 3))
                path.addLine(to: CGPoint(x: w, y: h / 3))
                path.move(to: CGPoint(x: 0, y: 2 * h / 3))
                path.addLine(to: CGPoint(x: w, y: 2 * h / 3))
            }
            .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
        }
    }
}

// MARK: - Camera Preview Container

private struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {}

    final class PreviewContainerView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
