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

    /// Checks if device has 48MP Pro sensor capabilities (Quad-Pixel 48MP on iPhone 14 Pro/15 Pro/16 Pro)
    static var has48MPFusionSensor: Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return false }
        for format in device.formats {
            // Check iOS 16+ supportedMaxPhotoDimensions (8064 x 6048 = 48MP)
            for dim in format.supportedMaxPhotoDimensions {
                if dim.width >= 7000 || dim.height >= 5000 {
                    return true
                }
            }
            // Check secondary native resolution zoom factors (2x sensor crop on 48MP Quad-Pixel)
            if !format.secondaryNativeResolutionZoomFactors.isEmpty {
                return true
            }
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            if dims.width >= 7000 || dims.height >= 5000 {
                return true
            }
        }
        // iPhone Pro models with Triple Camera and LiDAR always feature the 48MP sensor
        if supportsObjectCapture && AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) != nil {
            return true
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

    /// Factory optical calibration between lenses and LiDAR sensor
    static var hasMulticameraCalibration: Bool {
        guard let rear = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return false }
        if let ultraWide = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back),
           AVCaptureDevice.extrinsicMatrix(from: rear, to: ultraWide) != nil {
            return true
        }
        if let tele = AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back),
           AVCaptureDevice.extrinsicMatrix(from: rear, to: tele) != nil {
            return true
        }
        if let lidar = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back),
           AVCaptureDevice.extrinsicMatrix(from: rear, to: lidar) != nil {
            return true
        }
        return AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) != nil
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
            ("Calibración Óptica Multilente & LiDAR", hasMulticameraCalibration)
        ]
    }
}
