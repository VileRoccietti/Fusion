import SwiftUI

/// Main application root view with dark sleek glassmorphic navigation
struct RootView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Cámara & Cine", systemImage: "camera.aperture", value: 0) {
                ProCameraView()
            }

            Tab("Escanear 3D", systemImage: "cube.transparent", value: 1) {
                NavigationStack {
                    ScanSetupView()
                }
            }

            Tab("LiDAR Live", systemImage: "point.3.filled.connected.triangle.path.dotted", value: 2) {
                HegesLiveStreamView()
            }

            Tab("Estudio & AR", systemImage: "arkit", value: 3) {
                NavigationStack {
                    LibraryView()
                }
            }

            Tab("Galería Pro", systemImage: "photo.stack", value: 4) {
                NavigationStack {
                    MediaGalleryView()
                }
            }
        }
        .tint(.yellow)
    }
}
