import ARKit
import AVFoundation
import RealityKit
import RoomPlan
import SwiftUI

/// Hardware inspection and capability detection optimized for iPhone 16 Pro Max and LiDAR devices.
@MainActor
enum DeviceCapabilities {

    /// Apple RealityKit Guided Object Capture (LiDAR + Photogrammetry)
    static var supportsObjectCapture: Bool {
        ObjectCaptureSession.isSupported
    }

    /// On-device photogrammetry reconstruction
    static var supportsPhotogrammetry: Bool {
        PhotogrammetrySession.isSupported
    }

    /// Front TrueDepth structured light IR sensor
    static var hasTrueDepthCamera: Bool {
        AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) != nil
    }

    /// LiDAR mesh scene reconstruction
    static var supportsSceneReconstruction: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    /// Apple RoomPlan LiDAR room capture
    static var supportsRoomCapture: Bool {
        RoomCaptureSession.isSupported
    }

    /// Camera authorization state
    static var cameraAuthorization: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// Request camera permissions
    static func requestCameraAccess() async -> Bool {
        if cameraAuthorization == .authorized { return true }
        return await AVCaptureDevice.requestAccess(for: .video)
    }

    // MARK: - iPhone 16 Pro Max Camera Inventory

    /// Enumerates all available rear lenses (Main 48MP, Ultra Wide 48MP, Telephoto 5x 120mm, LiDAR)
    static var rearCaptureDevices: [(label: String, isVirtual: Bool)] {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera,
            .builtInLiDARDepthCamera,
            .builtInDualCamera,
            .builtInDualWideCamera,
            .builtInTripleCamera,
        ]

        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .back
        )

        return session.devices.map { device in
            (label: device.localizedName, isVirtual: !device.constituentDevices.isEmpty)
        }
    }

    static var physicalRearLensCount: Int {
        rearCaptureDevices.filter { !$0.isVirtual }.count
    }

    /// Checks if device has 48MP Pro sensor capabilities
    static var has48MPFusionSensor: Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return false }
        for format in device.formats {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            if dims.width >= 8000 || dims.height >= 6000 {
                return true
            }
        }
        return false
    }

    /// Returns a blocking hardware warning if essential scanner hardware is missing
    static var blockingHardwareWarning: String? {
        if AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) == nil {
            return "No se detectó la cámara trasera principal."
        }
        if !supportsObjectCapture {
            return "Object Capture no es compatible con este dispositivo. Se requiere un iPhone con LiDAR (iPhone 12 Pro o posterior, ej. iPhone 16 Pro Max)."
        }
        if !supportsPhotogrammetry {
            return "Este dispositivo no soporta fotogrametría integrada en el dispositivo."
        }
        return nil
    }

    /// Factory calibration between front and rear sensors
    static var hasFrontToRearCalibration: Bool {
        guard let rear = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let front = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front)
        else { return false }
        return AVCaptureDevice.extrinsicMatrix(from: rear, to: front) != nil
    }

    /// Hardware capabilities summary list for pre-flight diagnostics
    static var summary: [(label: String, value: Bool)] {
        [
            ("Object Capture (LiDAR 3D)", supportsObjectCapture),
            ("Fotogrametría Integrada", supportsPhotogrammetry),
            ("Escaneo de Habitaciones (RoomPlan)", supportsRoomCapture),
            ("Malla de Escena LiDAR", supportsSceneReconstruction),
            ("Cámara LiDAR de Profundidad", AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) != nil),
            ("Sensor Fusion 48MP", has48MPFusionSensor),
            ("Cámara Ultra Gran Angular", AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) != nil),
            ("Teleobjetivo Tetraprisma (5x)", AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back) != nil),
            ("Sensor TrueDepth Frontal", hasTrueDepthCamera),
            ("Calibración Frontal ↔ Trasera", hasFrontToRearCalibration)
        ]
    }
}
