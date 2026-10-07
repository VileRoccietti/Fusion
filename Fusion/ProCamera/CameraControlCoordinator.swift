import AVFoundation
import UIKit

/// Integrates with the physical Camera Control button on iPhone 16 Pro Max in iOS 18+
@MainActor
final class CameraControlCoordinator: NSObject {
    private weak var session: AVCaptureSession?

    init(session: AVCaptureSession) {
        self.session = session
        super.init()
    }

    func setupControlsIfAvailable() {
        guard let session else { return }

        // iOS 18 Camera Control API
        #if compiler(>=6.0)
        if #available(iOS 18.0, *) {
            guard session.supportsControls else { return }

            // Exposure Bias Slider on physical Camera Control
            let exposureSlider = AVCaptureSystemExposureBiasSlider(device: AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)!) { [weak self] bias in
                guard self != nil else { return }
                // Handle exposure control from button
            }

            if session.canAddControl(exposureSlider) {
                session.addControl(exposureSlider)
            }
        }
        #endif
    }
}
