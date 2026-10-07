import AVKit
import SwiftUI

/// Premium cinematic media gallery for ProRAW photos, 4K/120 videos, 3D scans, and night vision
struct MediaGalleryView: View {
    @State private var selectedFilter: GalleryFilter = .all
    @State private var selectedItem: MediaItem? = nil
    @State private var items: [MediaItem] = []
    @State private var showARViewer = false
    @State private var arModelURL: URL? = nil

    enum GalleryFilter: String, CaseIterable, Identifiable {
        case all = "Todo"
        case photo = "ProRAW"
        case video = "Videos 4K"
        case scan3D = "Modelos 3D"
        case nightVision = "Nocturno"

        var id: String { rawValue }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var filteredItems: [MediaItem] {
        switch selectedFilter {
        case .all: items
        case .photo: items.filter { $0.kind == .photo }
        case .video: items.filter { $0.kind == .video }
        case .scan3D: items.filter { $0.kind == .scan3D }
        case .nightVision: items.filter { $0.kind == .nightVision }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Filter Chips Bar
                    filterChipsBar
                        .padding(.vertical, 12)

                    // Content Grid
                    if filteredItems.isEmpty {
                        emptyStateView
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(filteredItems) { item in
                                    MediaCardView(item: item) {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            selectedItem = item
                                        }
                                        HapticFeedback.light()
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 32)
                        }
                    }
                }
            }
            .navigationTitle("Galería Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(items.count) elementos")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.yellow)
                }
            }
            .onAppear {
                loadCapturedMedia()
            }
            .fullScreenCover(item: $selectedItem) { item in
                MediaDetailViewer(item: item) { url in
                    self.arModelURL = url
                    self.showARViewer = true
                }
            }
            .fullScreenCover(isPresented: $showARViewer) {
                if let url = arModelURL {
                    ARImmersiveScanView(modelURL: url, scanName: url.deletingPathExtension().lastPathComponent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Filter Bar

    private var filterChipsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GalleryFilter.allCases) { filter in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            selectedFilter = filter
                        }
                        HapticFeedback.selection()
                    } label: {
                        Text(filter.rawValue)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                selectedFilter == filter ? Color.yellow : Color.white.opacity(0.12),
                                in: Capsule()
                            )
                            .foregroundStyle(selectedFilter == filter ? Color.black : Color.white)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "photo.stack")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.3))
            Text("No hay capturas en esta categoría")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))
            Text("Toma fotos ProRAW, graba videos 4K a 120 FPS o escanea objetos con LiDAR.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Media Loading

    private func loadCapturedMedia() {
        var list: [MediaItem] = []
        let fm = FileManager.default

        // 1. Scans in Scans Directory
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let scansDir = docs.appendingPathComponent("Scans", isDirectory: true)

        if let dirs = try? fm.contentsOfDirectory(at: scansDir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) {
            for dir in dirs {
                let modelFile = dir.appendingPathComponent("model.usdz")
                if fm.fileExists(atPath: modelFile.path(percentEncoded: false)) {
                    let attrs = try? fm.attributesOfItem(atPath: modelFile.path(percentEncoded: false))
                    let size = attrs?[.size] as? Int64 ?? 0
                    let date = attrs?[.modificationDate] as? Date ?? Date()

                    list.append(MediaItem(
                        id: UUID(),
                        title: dir.lastPathComponent,
                        kind: .scan3D,
                        date: date,
                        fileURL: modelFile,
                        thumbnailURL: nil,
                        fileSizeFormatted: String(format: "%.1f MB", Double(size) / 1_000_000.0),
                        resolutionText: "Malla 3D LiDAR",
                        lensText: "LiDAR + Fotogrametría",
                        isoText: nil,
                        shutterText: nil,
                        fpsText: nil
                    ))
                }
            }
        }

        // 2. Videos in Temp / Local
        let temp = fm.temporaryDirectory
        if let files = try? fm.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil) {
            for f in files where f.pathExtension.lowercased() == "mov" {
                let attrs = try? fm.attributesOfItem(atPath: f.path(percentEncoded: false))
                let size = attrs?[.size] as? Int64 ?? 0
                let date = attrs?[.modificationDate] as? Date ?? Date()

                list.append(MediaItem(
                    id: UUID(),
                    title: f.deletingPathExtension().lastPathComponent,
                    kind: .video,
                    date: date,
                    fileURL: f,
                    thumbnailURL: nil,
                    fileSizeFormatted: String(format: "%.1f MB", Double(size) / 1_000_000.0),
                    resolutionText: "4K UHD (3840x2160)",
                    lensText: "24mm f/1.78",
                    isoText: "ISO 100",
                    shutterText: "1/240s",
                    fpsText: "120 FPS"
                ))
            }
        }

        self.items = list.sorted(by: { $0.date > $1.date })
    }
}

// MARK: - Media Card View

private struct MediaCardView: View {
    let item: MediaItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.08))
                        .aspectRatio(1.0, contentMode: .fit)

                    // Fallback Icon Badge
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: item.kind.icon)
                                .font(.system(size: 32))
                                .foregroundStyle(.white.opacity(0.2))
                            Spacer()
                        }
                        Spacer()
                    }

                    // Kind Badge
                    HStack(spacing: 4) {
                        Image(systemName: item.kind.icon)
                            .font(.system(size: 9))
                        Text(item.kind.rawValue)
                            .font(.system(size: 9, weight: .bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.75), in: Capsule())
                    .foregroundStyle(.yellow)
                    .padding(8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )

                // Title & Details
                Text(item.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack {
                    Text(item.resolutionText)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text(item.fileSizeFormatted)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.yellow)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Media Detail Fullscreen Viewer

private struct MediaDetailViewer: View {
    let item: MediaItem
    let onOpenAR: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button {
                        dismiss()
                        HapticFeedback.light()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    Spacer()

                    ShareLink(item: item.fileURL) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 44)

                Spacer()

                // Content Viewer
                if item.kind == .video {
                    VideoPlayer(player: AVPlayer(url: item.fileURL))
                        .frame(maxHeight: 450)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .padding(.horizontal, 16)
                } else if item.kind == .scan3D {
                    VStack(spacing: 16) {
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 80))
                            .foregroundStyle(.yellow)

                        Text(item.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)

                        Button {
                            onOpenAR(item.fileURL)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arkit")
                                Text("Ver en Realidad Aumentada (AR)")
                            }
                            .font(.headline.weight(.black))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(Color.yellow, in: Capsule())
                            .foregroundStyle(.black)
                        }
                    }
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 80))
                        .foregroundStyle(.white.opacity(0.3))
                }

                Spacer()

                // Technical Metadata Card
                VStack(spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("INFORMACIÓN TÉCNICA")
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                            Text(item.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        Text(item.fileSizeFormatted)
                            .font(.headline.weight(.black))
                            .foregroundStyle(.yellow)
                    }

                    Divider().background(Color.white.opacity(0.2))

                    HStack {
                        metaPill(label: "RESOLUCIÓN", value: item.resolutionText)
                        Spacer()
                        metaPill(label: "LENTE", value: item.lensText)
                        if let fps = item.fpsText {
                            Spacer()
                            metaPill(label: "TASA", value: fps)
                        }
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }

    private func metaPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
        }
    }
}
