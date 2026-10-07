import AVFoundation
import CoreImage
import Foundation
import Observation
import SwiftUI
import UIKit
import os

/// Supported physical lenses on iPhone 16 Pro Max
enum ProLens: String, CaseIterable, Identifiable, Sendable {
    case ultraWide = "0.5x"
    case wide = "1x"
    case wideCrop = "2x"
    case telephoto = "5x"

    var id: String { rawValue }

    var label: String { rawValue }

    var focalLengthEquivalent: String {
        switch self {
        case .ultraWide: "13 mm"
        case .wide: "24 mm"
        case .wideCrop: "48 mm"
        case .telephoto: "120 mm"
        }
    }
}

/// Professional manual camera engine managing sensors, exposure, focus peaking, and 48MP ProRAW
@MainActor
@Observable
final class ProCameraEngine: NSObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    private static let logger = Logger(subsystem: "com.vileroccietti.Fusion", category: "procamera")

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let cameraQueue = DispatchQueue(label: "com.vileroccietti.Fusion.cameraQueue")

    private(set) var activeDevice: AVCaptureDevice?
    private(set) var activeLens: ProLens = .wide

    // Live state
    private(set) var isRunning = false
    var isManualExposure = false
    var isManualFocus = false
    var isManualWB = false

    // Camera parameters
    var currentISO: Float = 100
    var minISO: Float = 25
    var maxISO: Float = 3000

    var currentShutter: Double = 1.0 / 125.0
    var exposureBias: Float = 0.0

    var currentFocus: Float = 0.5 // 0.0 near, 1.0 far
    var currentKelvin: Int = 5500

    // Pro toggles
    var isProRAWEnabled = false
    var is48MPEnabled = true
    var isFocusPeakingEnabled = false
    var isZebraEnabled = false
    var isHistogramEnabled = true

    // Real-time histogram bins (64 normalized values)
    private(set) var histogramBins: [Float] = Array(repeating: 0.1, count: 64)

    // Capture feedback
    private(set) var isCapturing = false
    private(set) var lastCapturedImage: UIImage?

    override init() {
        super.init()
    }

    // MARK: - Lifecycle

    func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            session.commitConfiguration()
            return
        }
        self.activeDevice = device
        self.minISO = device.activeFormat.minISO
        self.maxISO = device.activeFormat.maxISO

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }

            if session.canAddOutput(photoOutput) {
                photoOutput.maxPhotoQualityPrioritization = .quality
                if photoOutput.isAppleProRAWSupported {
                    photoOutput.isAppleProRAWEnabled = isProRAWEnabled
                }
                session.addOutput(photoOutput)
            }

            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: cameraQueue)
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }

        } catch {
            Self.logger.error("Error al configurar la cámara: \(error.localizedDescription, privacy: .public)")
        }

        session.commitConfiguration()
    }

    func start() {
        guard !session.isRunning else { return }
        cameraQueue.async { [weak self] in
            self?.session.startRunning()
            Task { @MainActor in self?.isRunning = true }
        }
    }

    func stop() {
        guard session.isRunning else { return }
        cameraQueue.async { [weak self] in
            self?.session.stopRunning()
            Task { @MainActor in self?.isRunning = false }
        }
    }

    // MARK: - Lens Switching

    func switchLens(_ lens: ProLens) {
        guard activeLens != lens else { return }
        activeLens = lens
        HapticFeedback.selection()

        session.beginConfiguration()

        let deviceType: AVCaptureDevice.DeviceType
        var zoomFactor: CGFloat = 1.0

        switch lens {
        case .ultraWide:
            deviceType = .builtInUltraWideCamera
        case .wide:
            deviceType = .builtInWideAngleCamera
        case .wideCrop:
            deviceType = .builtInWideAngleCamera
            zoomFactor = 2.0
        case .telephoto:
            deviceType = .builtInTelephotoCamera
        }

        if let newDevice = AVCaptureDevice.default(deviceType, for: .video, position: .back) {
            // Remove old input
            if let currentInput = session.inputs.first as? AVCaptureDeviceInput {
                session.removeInput(currentInput)
            }

            if let newInput = try? AVCaptureDeviceInput(device: newDevice), session.canAddInput(newInput) {
                session.addInput(newInput)
                self.activeDevice = newDevice
                self.minISO = newDevice.activeFormat.minISO
                self.maxISO = newDevice.activeFormat.maxISO

                do {
                    try newDevice.lockForConfiguration()
                    if zoomFactor > 1.0 && zoomFactor <= newDevice.activeFormat.videoMaxZoomFactor {
                        newDevice.videoZoomFactor = zoomFactor
                    }
                    newDevice.unlockForConfiguration()
                } catch {}
            }
        }

        session.commitConfiguration()
    }

    // MARK: - Manual Controls

    func setManualExposure(shutter: Double, iso: Float) {
        guard let device = activeDevice else { return }
        isManualExposure = true
        currentShutter = shutter
        currentISO = iso

        cameraQueue.async {
            do {
                try device.lockForConfiguration()
                let duration = CMTime(seconds: shutter, preferredTimescale: 1_000_000)
                device.setExposureModeCustom(duration: duration, iso: iso)
                device.unlockForConfiguration()
            } catch {}
        }
    }

    func setExposureBias(_ bias: Float) {
        guard let device = activeDevice else { return }
        exposureBias = bias

        cameraQueue.async {
            do {
                try device.lockForConfiguration()
                device.setExposureTargetBias(bias)
                device.unlockForConfiguration()
            } catch {}
        }
    }

    func setManualFocus(_ position: Float) {
        guard let device = activeDevice else { return }
        isManualFocus = true
        currentFocus = position

        cameraQueue.async {
            do {
                try device.lockForConfiguration()
                device.setFocusModeLocked(lensPosition: position)
                device.unlockForConfiguration()
            } catch {}
        }
    }

    func setManualKelvin(_ kelvin: Int) {
        guard let device = activeDevice else { return }
        isManualWB = true
        currentKelvin = kelvin

        cameraQueue.async {
            do {
                try device.lockForConfiguration()
                let tempGains = device.deviceWhiteBalanceGains(for: AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                    temperature: Float(kelvin),
                    tint: 0
                ))
                device.setWhiteBalanceModeLocked(with: tempGains)
                device.unlockForConfiguration()
            } catch {}
        }
    }

    func resetToAuto() {
        guard let device = activeDevice else { return }
        isManualExposure = false
        isManualFocus = false
        isManualWB = false
        exposureBias = 0

        cameraQueue.async {
            do {
                try device.lockForConfiguration()
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
                device.setExposureTargetBias(0)
                device.unlockForConfiguration()
            } catch {}
        }
        HapticFeedback.medium()
    }

    // MARK: - Capture

    func capturePhoto() {
        guard session.isRunning, !isCapturing else { return }
        isCapturing = true
        HapticFeedback.heavy()

        var settings: AVCapturePhotoSettings
        if isProRAWEnabled && photoOutput.availableRawPhotoPixelFormatTypes.contains(kCVPixelFormatType_14Bayer_RGGB) {
            settings = AVCapturePhotoSettings(rawPixelFormatType: kCVPixelFormatType_14Bayer_RGGB)
        } else {
            settings = AVCapturePhotoSettings()
        }

        settings.photoQualityPrioritization = .quality

        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func finishCaptureOnMain(image: UIImage?) {
        self.lastCapturedImage = image
        self.isCapturing = false
        if image != nil {
            HapticFeedback.success()
        }
    }

    private func updateHistogramOnMain(_ bins: [Float]) {
        self.histogramBins = bins
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            Task { @MainActor [weak self] in
                self?.finishCaptureOnMain(image: nil)
            }
            return
        }

        let image = UIImage(data: data)

        // Save to system Photo Library
        if let image {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        }

        Task { @MainActor [weak self] in
            self?.finishCaptureOnMain(image: image)
        }
    }

    // MARK: - Video Frame Processing (Live Histogram)

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        // Subsample for 64-bin luminance histogram
        var buckets = [Int](repeating: 0, count: 64)
        let step = 8
        var sampleCount = 0

        for y in stride(from: 0, to: height, by: step) {
            let row = buffer.advanced(by: y * bytesPerRow)
            for x in stride(from: 0, to: width, by: step) {
                // BGRA format
                let b = Float(row[x * 4])
                let g = Float(row[x * 4 + 1])
                let r = Float(row[x * 4 + 2])
                let luma = Int((0.299 * r + 0.587 * g + 0.114 * b) / 255.0 * 63.0)
                let bucketIndex = min(max(luma, 0), 63)
                buckets[bucketIndex] += 1
                sampleCount += 1
            }
        }

        let maxCount = Float(buckets.max() ?? 1)
        let normalized = buckets.map { Float($0) / max(maxCount, 1.0) }

        Task { @MainActor [weak self] in
            self?.updateHistogramOnMain(normalized)
        }
    }
}
