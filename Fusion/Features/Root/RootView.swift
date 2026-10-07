import SwiftUI

/// Main application root view with dark sleek glassmorphic navigation
struct RootView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Escanear 3D", systemImage: "cube.transparent", value: 0) {
                NavigationStack {
                    ScanSetupView()
                }
            }

            Tab("Cámara Pro", systemImage: "camera.aperture", value: 1) {
                ProCameraView()
            }

            Tab("Estudio 3D", systemImage: "square.stack.3d.up.fill", value: 2) {
                NavigationStack {
                    LibraryView()
                }
            }
        }
        .tint(.yellow)
    }
}
