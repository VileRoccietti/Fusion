import SwiftUI

@main
struct FusionApp: App {
    @State private var storage = ScanStorage()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(storage)
                .preferredColorScheme(.dark)
        }
    }
}
