import AVFoundation
import AVKit
import SwiftUI

/// Professional and automatic cinematic video studio view for iPhone 16 Pro Max
struct ProVideoView: View {
    @Binding var currentMode: CameraHubMode
    @State private var engine = ProVideoEngine()
    @State private var showZoomWheel = false
    @State private var selectedTab: ProVideoTab = .framerate
    @State private var tapFocusLocation: CGPoint? = nil
    @State private var focusBoxExposureOffset: CGFloat = 0
    @State private var showPlaybackSheet = false
    @State private var showToolsSheet = false

    init(currentMode: Binding<CameraHubMode>? = nil) {
        self._currentMode = currentMode ?? .constant(.video)
    }

    enum ProVideoTab: String, CaseIterable, Identifiable {
        case framerate = "FPS / 4K"
        case shutter = "OBTURADOR"
        case iso = "ISO / EV"
        case focus = "ENFOQUE"
        case wb = "WB"
        case look = "LOOK"
        case guides = "GUÍAS"

        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Viewfinder with optional Anamorphic scaling
            viewfinderArea
                .ignoresSafeArea()

            // Tap Focus Box with interactive Exposure Slider
            if let loc = tapFocusLocation {
                focusReticleView(at: loc)
            }

            // Aspect Ratio Letterbox / Pillarbox Matte
            if let ratio = engine.selectedAspectRatio.ratioValue {
                AspectMaskOverlay(aspectRatio: ratio)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // False Color IRE Exposure Simulation Overlay
            if engine.isFalseColorActive {
                FalseColorSimulationOverlay()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Zebra Pattern Simulation Overlay
            if engine.isZebraActive {
                ZebraStripesOverlay()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Audio Stereo VU Meters (Left Side)
            if engine.isProMode {
                VStack {
                    Spacer()
                    StereoVUMeterView(leftLevel: engine.audioLevelLeft, rightLevel: engine.audioLevelRight)
                        .padding(.leading, 12)
                        .padding(.bottom, 170)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // UI Chrome Overlay
            VStack(spacing: 0) {
                topNavigationBar

                Spacer()

                // Radial Zoom Wheel if opened
                if showZoomWheel {
                    ZoomWheelControl(zoomFactor: $engine.zoomFactor)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Normal Mode Lens Pills (0.5x, 1x, 2x, 5x)
                if !engine.isProMode && !showZoomWheel {
                    normalModeLensPillRow
                        .padding(.bottom, 10)
                }

                // Pro Mode Cinema Deck
                if engine.isProMode {
                    proControlDeck
                        .padding(.bottom, 6)
                }

                // Bottom Record & Shutter Bar
                bottomActionBar
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            engine.configure()
            engine.start()
        }
        .onDisappear {
            engine.stop()
        }
        .sheet(isPresented: $showPlaybackSheet) {
            if let url = engine.lastRecordedURL {
                VideoPlayerSheet(url: url)
            }
        }
    }

    // MARK: - Viewfinder Area

    private var viewfinderArea: some View {
        GeometryReader { geo in
            VideoCameraPreview(session: engine.session)
                .scaleEffect(x: engine.selectedAnamorphic.scaleFactor, y: 1.0)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .onTapGesture { location in
                    tapFocusLocation = location
                    focusBoxExposureOffset = 0
                    engine.tapToFocusAndExpose(at: location)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        if tapFocusLocation == location {
                            tapFocusLocation = nil
                        }
                    }
                }
        }
    }

    // MARK: - Tap Focus Reticle with Vertical Drag Exposure

    private func focusReticleView(at point: CGPoint) -> some View {
        ZStack {
            // Yellow square
            Rectangle()
                .stroke(Color.yellow, lineWidth: 1.5)
                .frame(width: 66, height: 66)

            // Center crosshair
            Circle()
                .fill(Color.yellow)
                .frame(width: 4, height: 4)

            // Vertical Sun Exposure Slider
            VStack(spacing: 2) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.yellow)
                Rectangle()
                    .fill(Color.yellow.opacity(0.8))
                    .frame(width: 2, height: 40)
            }
            .offset(x: 48, y: focusBoxExposureOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        focusBoxExposureOffset = max(-30, min(30, value.translation.height))
                        let evDelta = Float(-value.translation.height / 10.0)
                        engine.exposureBias = max(-3.0, min(3.0, evDelta))
                    }
            )
        }
        .position(point)
        .animation(.spring(response: 0.25), value: point)
    }

    // MARK: - Top Navigation Bar

    private var topNavigationBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                // AUTO vs PRO CINE Mode Pill Switcher
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        engine.isProMode.toggle()
                    }
                    HapticFeedback.selection()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: engine.isProMode ? "film.stack.fill" : "wand.and.stars")
                            .font(.system(size: 11, weight: .bold))
                        Text(engine.isProMode ? "PRO CINE" : "NORMAL")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        engine.isProMode ?
                            LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing) :
                            LinearGradient(colors: [Color.white.opacity(0.2), Color.white.opacity(0.1)], startPoint: .leading, endPoint: .trailing),
                        in: Capsule()
                    )
                    .foregroundStyle(engine.isProMode ? Color.black : Color.white)
                    .shadow(color: engine.isProMode ? Color.yellow.opacity(0.3) : Color.clear, radius: 8)
                }

                // Timecode & Status Badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(engine.isRecording ? Color.red : Color.white.opacity(0.4))
                        .frame(width: 8, height: 8)
                        .opacity(engine.isRecording ? 1.0 : 0.6)

                    Text(engine.isRecording ? "REC" : "STBY")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(engine.isRecording ? Color.red : Color.white.opacity(0.6))

                    Text(engine.timecodeString)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(engine.isRecording ? Color.red : Color.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.black.opacity(0.65), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.8))

                Spacer()

                // Torch Toggle
                Button {
                    engine.isTorchActive.toggle()
                    HapticFeedback.light()
                } label: {
                    Image(systemName: engine.isTorchActive ? "bolt.fill" : "bolt.slash.fill")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 32, height: 32)
                        .background(engine.isTorchActive ? Color.yellow : Color.black.opacity(0.5), in: Circle())
                        .foregroundStyle(engine.isTorchActive ? Color.black : Color.white)
                }

                // Quick Resolution & FPS Pill (Tappable in both modes)
                Menu {
                    Section("Resolución") {
                        Button("4K Ultra HD (3840x2160)") { engine.targetResolution4K = true }
                        Button("1080p Full HD (1920x1080)") { engine.targetResolution4K = false }
                    }
                    Section("Fotogramas por Segundo") {
                        Button("24 FPS (Cinematográfico)") { engine.currentFPS = 24 }
                        Button("25 FPS (PAL Europa)") { engine.currentFPS = 25 }
                        Button("30 FPS (Estándar)") { engine.currentFPS = 30 }
                        Button("48 FPS (HFR Cine)") { engine.currentFPS = 48 }
                        Button("50 FPS (PAL 50)") { engine.currentFPS = 50 }
                        Button("60 FPS (Ultra Fluido)") { engine.currentFPS = 60 }
                        Button("120 FPS (4K Slow-Mo A18 Pro)") { engine.currentFPS = 120 }
                    }
                } label: {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(engine.targetResolution4K ? "4K UHD" : "1080p")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(.yellow)
                        Text("\(engine.currentFPS) FPS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.15), lineWidth: 0.8))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 48)
    }

    // MARK: - Normal Mode Lens Pills

    private var normalModeLensPillRow: some View {
        HStack(spacing: 12) {
            ForEach(CineLens.allCases) { lens in
                Button {
                    engine.activeLens = lens
                } label: {
                    Text(lens == .ultraWide ? ".5" : (lens == .wide ? "1x" : (lens == .twoX ? "2" : "5")))
                        .font(.system(size: 12, weight: engine.activeLens == lens ? .black : .bold))
                        .frame(width: 38, height: 38)
                        .background(engine.activeLens == lens ? Color.yellow : Color.black.opacity(0.55), in: Circle())
                        .foregroundStyle(engine.activeLens == lens ? Color.black : Color.white)
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.8))
                }
            }
        }
    }

    // MARK: - Pro Control Deck

    private var proControlDeck: some View {
        VStack(spacing: 8) {
            // Horizontal Tab Selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ProVideoTab.allCases) { tab in
                        Button {
                            withAnimation(.spring(response: 0.25)) {
                                selectedTab = tab
                            }
                            HapticFeedback.selection()
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(selectedTab == tab ? Color.yellow : Color.black.opacity(0.65), in: Capsule())
                                .foregroundStyle(selectedTab == tab ? Color.black : Color.white)
                                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.6))
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            // Subdeck Parameters Box
            VStack(spacing: 8) {
                switch selectedTab {
                case .framerate:
                    framerateSubdeck
                case .shutter:
                    shutterSubdeck
                case .iso:
                    isoSubdeck
                case .focus:
                    focusSubdeck
                case .wb:
                    wbSubdeck
                case .look:
                    lookSubdeck
                case .guides:
                    guidesSubdeck
                }
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .padding(.horizontal, 14)
        }
    }

    // MARK: - Subdecks

    private var framerateSubdeck: some View {
        VStack(spacing: 8) {
            // Preset frame rates row
            HStack(spacing: 5) {
                ForEach([24, 25, 30, 48, 50, 60, 120], id: \.self) { fps in
                    Button {
                        engine.currentFPS = fps
                        HapticFeedback.selection()
                    } label: {
                        Text("\(fps)")
                            .font(.system(size: 11, weight: engine.currentFPS == fps ? .black : .bold, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(engine.currentFPS == fps ? Color.yellow : Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(engine.currentFPS == fps ? Color.black : Color.white)
                    }
                }
            }

            // Custom Arbitrary FPS Stepper & Slider
            HStack(spacing: 12) {
                Text("FPS LIBRE:")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.yellow)

                Slider(
                    value: Binding(
                        get: { Double(engine.currentFPS) },
                        set: { engine.setCustomFPS(Int($0)) }
                    ),
                    in: 1...120,
                    step: 1
                )
                .tint(.yellow)

                Text("\(engine.currentFPS) FPS")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 60, alignment: .trailing)
            }
        }
    }

    private var shutterSubdeck: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(ShutterAngle.allCases) { angle in
                    Button {
                        engine.selectedShutterAngle = angle
                        HapticFeedback.selection()
                    } label: {
                        Text(angle.rawValue)
                            .font(.system(size: 10, weight: engine.selectedShutterAngle == angle ? .black : .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(engine.selectedShutterAngle == angle ? Color.yellow : Color.white.opacity(0.15), in: Capsule())
                            .foregroundStyle(engine.selectedShutterAngle == angle ? Color.black : Color.white)
                    }
                }
            }

            HStack(spacing: 10) {
                Text("VEL: 1/\(Int(1.0 / max(0.0001, engine.manualShutter)))s")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.yellow)

                if engine.selectedShutterAngle == .custom {
                    Slider(
                        value: Binding(
                            get: { log10(max(0.0001, engine.manualShutter)) },
                            set: { engine.manualShutter = pow(10, $0) }
                        ),
                        in: log10(1.0 / 4000.0)...log10(1.0 / 24.0)
                    )
                    .tint(.yellow)
                } else {
                    Text("Regla de 180° sincronizada a \(engine.currentFPS) FPS")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    private var isoSubdeck: some View {
        HStack(spacing: 12) {
            Button(engine.isAutoExposure ? "AUTO ISO" : "MANUAL") {
                engine.isAutoExposure.toggle()
                HapticFeedback.selection()
            }
            .font(.system(size: 10, weight: .black))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(engine.isAutoExposure ? Color.green : Color.white.opacity(0.2), in: Capsule())
            .foregroundStyle(engine.isAutoExposure ? Color.black : Color.white)

            Slider(value: $engine.manualISO, in: 25...2500, step: 25)
                .tint(.yellow)
                .disabled(engine.isAutoExposure)

            Text("ISO \(Int(engine.manualISO))")
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundStyle(.yellow)
                .frame(width: 70, alignment: .trailing)
        }
    }

    private var focusSubdeck: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button(engine.isAutoFocus ? "AUTO AF" : "MANUAL") {
                    engine.isAutoFocus.toggle()
                    HapticFeedback.selection()
                }
                .font(.system(size: 10, weight: .black))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(engine.isAutoFocus ? Color.green : Color.white.opacity(0.2), in: Capsule())
                .foregroundStyle(engine.isAutoFocus ? Color.black : Color.white)

                Slider(value: $engine.manualFocus, in: 0...1)
                    .tint(.green)
                    .disabled(engine.isAutoFocus)

                Text(String(format: "MF %.2f", engine.manualFocus))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green)
            }

            // Rack Focus Points Row
            HStack(spacing: 8) {
                Button(engine.rackFocusPointA != nil ? "PUNTO A ✓" : "GUARDAR A") {
                    engine.setRackFocusPoint(point: "A")
                }
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(engine.rackFocusPointA != nil ? Color.blue : Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(.white)

                Button(engine.rackFocusPointB != nil ? "PUNTO B ✓" : "GUARDAR B") {
                    engine.setRackFocusPoint(point: "B")
                }
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(engine.rackFocusPointB != nil ? Color.purple : Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(.white)

                if let ptA = engine.rackFocusPointA, let ptB = engine.rackFocusPointB {
                    Button("TRANSICIÓN A ⇄ B") {
                        let target = abs(engine.manualFocus - ptA) < abs(engine.manualFocus - ptB) ? ptB : ptA
                        engine.transitionRackFocus(toTarget: target)
                    }
                    .font(.system(size: 9, weight: .black))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.yellow, in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.black)
                }

                Spacer()

                // Focus Peaking Toggle
                Button {
                    engine.isFocusPeakingActive.toggle()
                    HapticFeedback.light()
                } label: {
                    Image(systemName: "circle.dotted")
                        .font(.system(size: 11, weight: .bold))
                    Text("PEAK")
                        .font(.system(size: 9, weight: .black))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(engine.isFocusPeakingActive ? engine.focusPeakingColor.swiftUIColor : Color.white.opacity(0.15), in: Capsule())
                .foregroundStyle(engine.isFocusPeakingActive ? Color.black : Color.white)
            }
        }
    }

    private var wbSubdeck: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    wbPresetButton("🕯️ Vela", kelvin: 2500)
                    wbPresetButton("💡 Tungsteno", kelvin: 3200)
                    wbPresetButton("🏢 Fluorescente", kelvin: 4000)
                    wbPresetButton("☀️ Luz de Día", kelvin: 5600)
                    wbPresetButton("☁️ Nublado", kelvin: 6500)
                    wbPresetButton("🌲 Sombra", kelvin: 7500)
                }
            }

            HStack(spacing: 10) {
                Button(engine.isAutoWB ? "AWB" : "MANUAL") {
                    engine.isAutoWB.toggle()
                    HapticFeedback.selection()
                }
                .font(.system(size: 10, weight: .black))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(engine.isAutoWB ? Color.yellow : Color.white.opacity(0.2), in: Capsule())
                .foregroundStyle(engine.isAutoWB ? Color.black : Color.white)

                Slider(value: Binding(
                    get: { Double(engine.currentKelvin) },
                    set: { engine.currentKelvin = Int($0) }
                ), in: 2500...9500, step: 100)
                .tint(.orange)
                .disabled(engine.isAutoWB)

                Text("\(engine.currentKelvin) K")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
                    .frame(width: 55, alignment: .trailing)
            }
        }
    }

    private func wbPresetButton(_ title: String, kelvin: Int) -> some View {
        Button(title) {
            engine.setKelvinPreset(kelvin)
        }
        .font(.system(size: 10, weight: .bold))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(engine.currentKelvin == kelvin && !engine.isAutoWB ? Color.orange : Color.white.opacity(0.12), in: Capsule())
        .foregroundStyle(engine.currentKelvin == kelvin && !engine.isAutoWB ? Color.black : Color.white)
    }

    private var lookSubdeck: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CineColorGrade.allCases) { grade in
                    Button(grade.rawValue) {
                        engine.selectedColorGrade = grade
                        HapticFeedback.selection()
                    }
                    .font(.system(size: 10, weight: engine.selectedColorGrade == grade ? .black : .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(engine.selectedColorGrade == grade ? Color.yellow : Color.white.opacity(0.12), in: Capsule())
                    .foregroundStyle(engine.selectedColorGrade == grade ? Color.black : Color.white)
                }
            }
        }
    }

    private var guidesSubdeck: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(CineAspectRatio.allCases) { aspect in
                        Button(aspect.rawValue) {
                            engine.selectedAspectRatio = aspect
                            HapticFeedback.selection()
                        }
                        .font(.system(size: 10, weight: engine.selectedAspectRatio == aspect ? .black : .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(engine.selectedAspectRatio == aspect ? Color.yellow : Color.white.opacity(0.15), in: Capsule())
                        .foregroundStyle(engine.selectedAspectRatio == aspect ? Color.black : Color.white)
                    }
                }
            }

            HStack(spacing: 8) {
                // Anamorphic de-squeeze
                Menu {
                    ForEach(AnamorphicFactor.allCases) { factor in
                        Button(factor.rawValue) {
                            engine.selectedAnamorphic = factor
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.and.right")
                        Text(engine.selectedAnamorphic.rawValue)
                    }
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.15), in: Capsule())
                    .foregroundStyle(.white)
                }

                // Zebra stripes toggle
                Button("ZEBRAS") {
                    engine.isZebraActive.toggle()
                    HapticFeedback.light()
                }
                .font(.system(size: 10, weight: .black))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(engine.isZebraActive ? Color.yellow : Color.white.opacity(0.15), in: Capsule())
                .foregroundStyle(engine.isZebraActive ? Color.black : Color.white)

                // False color toggle
                Button("FALSE COLOR") {
                    engine.isFalseColorActive.toggle()
                    HapticFeedback.light()
                }
                .font(.system(size: 10, weight: .black))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(engine.isFalseColorActive ? Color.purple : Color.white.opacity(0.15), in: Capsule())
                .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        VStack(spacing: 8) {
            CameraModeSelectorRow(currentMode: $currentMode)
                .padding(.top, 2)

            HStack {
                // Zoom wheel toggle
                Button {
                    withAnimation(.spring(response: 0.25)) {
                        showZoomWheel.toggle()
                    }
                    HapticFeedback.selection()
                } label: {
                    Text(String(format: "%.1fx", engine.zoomFactor))
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .frame(width: 46, height: 46)
                        .background(showZoomWheel ? Color.yellow : Color.black.opacity(0.65), in: Circle())
                        .foregroundStyle(showZoomWheel ? Color.black : Color.white)
                        .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                }

                Spacer()

                // Tactical Red Shutter Button
                Button {
                    engine.toggleRecording()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 3.5)
                            .frame(width: 76, height: 76)

                        if engine.isRecording {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.red)
                                .frame(width: 32, height: 32)
                        } else {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 60, height: 60)
                        }
                    }
                }

                Spacer()

                // Last thumbnail & Playback Preview
                if let thumb = engine.lastThumbnail {
                    Button {
                        showPlaybackSheet = true
                    } label: {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.yellow, lineWidth: 1.5))
                            .overlay(
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white)
                                    .shadow(radius: 4)
                            )
                    }
                } else {
                    Color.clear.frame(width: 46, height: 46)
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 12)
        .background(.black.opacity(0.85))
    }
}

// MARK: - Aspect Mask Overlay

private struct AspectMaskOverlay: View {
    let aspectRatio: CGFloat

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let boxHeight = w / aspectRatio
            let margin = max(0, (h - boxHeight) / 2)

            VStack(spacing: 0) {
                Color.black.opacity(0.8)
                    .frame(height: margin)
                Spacer()
                Color.black.opacity(0.8)
                    .frame(height: margin)
            }
            .overlay(
                Rectangle()
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
                    .frame(width: w, height: boxHeight)
            )
        }
    }
}

// MARK: - Stereo VU Meter

private struct StereoVUMeterView: View {
    let leftLevel: Float
    let rightLevel: Float

    var body: some View {
        HStack(spacing: 3) {
            singleVUMeter(level: leftLevel)
            singleVUMeter(level: rightLevel)
        }
        .padding(4)
        .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.15), lineWidth: 0.5))
    }

    private func singleVUMeter(level: Float) -> some View {
        VStack(spacing: 2) {
            ForEach(0..<14) { i in
                let threshold = -48.0 + Float(13 - i) * 3.5
                Rectangle()
                    .fill(barColor(index: i, active: level >= threshold))
                    .frame(width: 4, height: 3)
            }
        }
    }

    private func barColor(index: Int, active: Bool) -> Color {
        guard active else { return Color.white.opacity(0.08) }
        if index < 2 { return .red }
        if index < 5 { return .yellow }
        return .green
    }
}

// MARK: - False Color Simulation Overlay

private struct FalseColorSimulationOverlay: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.purple.opacity(0.2),
                Color.blue.opacity(0.15),
                Color.green.opacity(0.15),
                Color.yellow.opacity(0.15),
                Color.red.opacity(0.25)
            ],
            startPoint: .bottomLeading,
            endPoint: .topTrailing
        )
        .blendMode(.color)
    }
}

// MARK: - Zebra Stripes Overlay

private struct ZebraStripesOverlay: View {
    var body: some View {
        Canvas { context, size in
            let stripeWidth: CGFloat = 8
            let count = Int((size.width + size.height) / stripeWidth)
            for i in stride(from: 0, to: count, by: 2) {
                let path = Path { p in
                    p.move(to: CGPoint(x: CGFloat(i) * stripeWidth, y: 0))
                    p.addLine(to: CGPoint(x: 0, y: CGFloat(i) * stripeWidth))
                }
                context.stroke(path, with: .color(Color.yellow.opacity(0.25)), lineWidth: 2)
            }
        }
    }
}

// MARK: - Video Preview Layer Container

private struct VideoCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewContainer {
        let view = PreviewContainer()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewContainer, context: Context) {}

    final class PreviewContainer: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

// MARK: - Video Player Quick Sheet

private struct VideoPlayerSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VideoPlayer(player: AVPlayer(url: url))
                .ignoresSafeArea()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                .navigationTitle("Vista Previa")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
