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
        if #available(iOS 18.0, *) {
            guard session.supportsControls else { return }
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }

            session.beginConfiguration()
            let exposureSlider = AVCaptureSystemExposureBiasSlider(device: device)
            if session.canAddControl(exposureSlider) {
                session.addControl(exposureSlider)
            }
            session.commitConfiguration()
        }
    }
}
