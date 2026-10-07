import AVFoundation
import SwiftUI

/// Professional manual camera studio view for iPhone 16 Pro Max
struct ProCameraView: View {
    @State private var engine = ProCameraEngine()
    @StateObject private var horizonGuide = HorizonLevelGuide()

    @State private var selectedControl: ManualControlTab = .exposure
    @State private var showGrid = true

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
            VStack {
                topToolbar
                Spacer()
                manualControlsBar
                bottomBar
            }
        }
        .preferredColorScheme(.dark)
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
        HStack(spacing: 14) {
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
        .padding(.top, 8)
    }

    // MARK: - Manual Controls Bar

    private var manualControlsBar: some View {
        VStack(spacing: 8) {
            // Slider depending on selected tab
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

            // Tab bar selector
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
        VStack(spacing: 12) {
            // Lens Picker
            HStack(spacing: 14) {
                ForEach(ProLens.allCases) { lens in
                    Button {
                        engine.switchLens(lens)
                    } label: {
                        Text(lens.label)
                            .font(.subheadline.weight(engine.activeLens == lens ? .bold : .medium))
                            .frame(width: 44, height: 44)
                            .background(engine.activeLens == lens ? Color.white.opacity(0.25) : Color.black.opacity(0.4), in: Circle())
                            .foregroundStyle(engine.activeLens == lens ? Color.yellow : Color.white)
                    }
                }
            }

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

                // Spacer to balance
                Color.clear
                    .frame(width: 48, height: 48)
            }
            .padding(.horizontal, 30)
        }
        .padding(.bottom, 16)
        .background(.black.opacity(0.8))
    }
}

// MARK: - Composition Grid

private struct CompositionGridView: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            Path { path in
                // Vertical thirds
                path.move(to: CGPoint(x: w / 3, y: 0))
                path.addLine(to: CGPoint(x: w / 3, y: h))
                path.move(to: CGPoint(x: 2 * w / 3, y: 0))
                path.addLine(to: CGPoint(x: 2 * w / 3, y: h))

                // Horizontal thirds
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
