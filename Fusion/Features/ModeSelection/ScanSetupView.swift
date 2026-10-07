import SwiftUI

/// Pre-flight scanner setup screen with object analysis, mode recommendations, and diagnostics
struct ScanSetupView: View {
    @Environment(ScanStorage.self) private var storage

    @State private var profile = ObjectProfile()
    @State private var overriddenKind: ScanEngineKind?
    @State private var isPresentingCapture = false
    @State private var permissionDenied = false

    private var availableKinds: Set<ScanEngineKind> {
        var kinds: Set<ScanEngineKind> = []
        if ObjectCaptureEngine.availability.isUsable { kinds.insert(.objectCapture) }
        if TurntableCaptureEngine.availability.isUsable { kinds.insert(.turntable) }
        if TrueDepthEngine.availability.isUsable { kinds.insert(.trueDepth) }
        if RoomCaptureEngine.availability.isUsable { kinds.insert(.roomPlan) }
        return kinds
    }

    private var recommendation: ModeRecommendation {
        profile.recommendation(availableKinds: availableKinds)
    }

    private var selectedKind: ScanEngineKind {
        overriddenKind ?? recommendation.kind
    }

    private var canStart: Bool {
        selectedKind.isImplemented && availableKinds.contains(selectedKind)
    }

    var body: some View {
        Form {
            hardwareWarningSection

            if selectedKind == .roomPlan {
                roomSection
            } else {
                objectSection
                recommendationSection
            }

            modeSection

            if selectedKind != .roomPlan {
                detailSection
            }

            diagnosticsSection
        }
        .navigationTitle("Nuevo Escaneo 3D")
        .safeAreaInset(edge: .bottom) { startButton }
        .fullScreenCover(isPresented: $isPresentingCapture) {
            switch selectedKind {
            case .objectCapture: ObjectCaptureFlowView()
            case .turntable: TurntableFlowView()
            case .trueDepth: TrueDepthFlowView()
            case .roomPlan: RoomFlowView()
            }
        }
        .alert("Acceso a la cámara restringido", isPresented: $permissionDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Ve a Configuración > ObjectScannerPro para permitir el acceso a la cámara.")
        }
        .onChange(of: profile) { _, _ in
            overriddenKind = nil
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var hardwareWarningSection: some View {
        if let warning = DeviceCapabilities.blockingHardwareWarning {
            Section {
                Label {
                    Text(warning)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "wrench.and.screwdriver.fill")
                }
                .foregroundStyle(.orange)
            } header: {
                Text("Aviso de Hardware")
            }
        }
    }

    private var objectSection: some View {
        Section {
            Picker("Tamaño", selection: $profile.size) {
                ForEach(ObjectProfile.Size.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("Acabado", selection: $profile.finish) {
                ForEach(ObjectProfile.Finish.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("Patrón", selection: $profile.pattern) {
                ForEach(ObjectProfile.Pattern.allCases) { Text($0.displayName).tag($0) }
            }
        } header: {
            Text("Características del Objeto")
        } footer: {
            Text("El patrón de textura es el factor más decisivo: la fotogrametría genera geometría a partir de contrastes y textura visual.")
        }
    }

    private var roomSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Escaneo Estructural con RoomPlan")
                    .font(.headline)
                Text("El sensor LiDAR detecta y clasifica paredes, puertas, ventanas y muebles en tiempo real con dimensiones métricas reales. Funciona de manera óptima incluso en paredes lisas sin textura.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()

                Label(
                    "El mobiliario se clasifica como volúmenes paramétricos limpios.",
                    systemImage: "cube.box.fill"
                )
                .font(.footnote)
                .foregroundStyle(.orange)

                Label(
                    "Exportación a escala milimétrica exacta.",
                    systemImage: "ruler"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Escaneo de Espacios")
        }
    }

    private var recommendationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: recommendation.kind.symbolName)
                        .font(.title2)
                        .foregroundStyle(recommendation.strength == .strong ? .green : .orange)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(recommendation.kind.displayName)
                                .font(.headline)
                            if let badge = recommendation.kind.maturity.badge {
                                Text(badge)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.orange.opacity(0.16), in: Capsule())
                            }
                        }
                        Text(recommendation.strength == .strong ? "Recomendado" : "Alternativa compatible")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(recommendation.strength == .strong ? .green : .orange)
                    }

                    Spacer()
                }

                Text(recommendation.rationale)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !recommendation.warnings.isEmpty || !recommendation.tips.isEmpty {
                    Divider()
                }

                ForEach(recommendation.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                ForEach(recommendation.tips, id: \.self) { tip in
                    Label(tip, systemImage: "lightbulb.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("Modo Recomendado")
        }
    }

    private var modeSection: some View {
        Section {
            ForEach(ScanEngineKind.allCases) { kind in
                HStack(spacing: 12) {
                    Image(systemName: kind.symbolName)
                        .font(.title3)
                        .frame(width: 28)
                        .foregroundStyle(kind == selectedKind ? .yellow : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(kind.displayName)
                                .font(.body.weight(kind == selectedKind ? .semibold : .regular))
                            if let badge = kind.maturity.badge {
                                Text(badge)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.orange.opacity(0.16), in: Capsule())
                            }
                        }
                        Text(kind.tagline)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if kind == selectedKind {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.yellow)
                    }
                }
                .contentShape(.rect)
                .onTapGesture {
                    overriddenKind = kind
                    HapticFeedback.selection()
                }
            }
        } header: {
            Text("Modos de Escaneo")
        }
    }

    private var detailSection: some View {
        Section {
            Label("Reconstrucción en dispositivo: Alta Velocidad", systemImage: "cpu")
                .font(.subheadline)
            Label("Las imágenes de origen se conservan para reconstrucción de máximo detalle (.raw) en Mac.", systemImage: "arrow.up.forward.app")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Detalle Poligonal")
        }
    }

    private var diagnosticsSection: some View {
        Section("Sensores del Dispositivo (iPhone 16 Pro Max)") {
            ForEach(DeviceCapabilities.summary, id: \.label) { item in
                HStack {
                    Text(item.label)
                    Spacer()
                    Image(systemName: item.value ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(item.value ? .green : .secondary)
                }
                .font(.subheadline)
            }
        }
    }

    private var startButton: some View {
        Button {
            Task {
                guard await DeviceCapabilities.requestCameraAccess() else {
                    permissionDenied = true
                    return
                }
                HapticFeedback.medium()
                isPresentingCapture = true
            }
        } label: {
            HStack {
                Image(systemName: "camera.viewfinder")
                Text("Iniciar Escaneo 3D")
            }
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.yellow, in: RoundedRectangle(cornerRadius: 14))
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}
