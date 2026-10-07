@preconcurrency import AVFoundation
import CoreImage
import Foundation
import Observation
import Photos
import SwiftUI
import UIKit
import os

/// Cinematic aspect ratio guides
enum CineAspectRatio: String, CaseIterable, Identifiable, Sendable {
    case off = "OFF"
    case scope239 = "2.39:1 Scope"
    case cinema185 = "1.85:1 Flat"
    case wide169 = "16:9 UHD"
    case classic43 = "4:3 Academy"
    case square11 = "1:1 Cuadrado"
    case vertical916 = "9:16 Reel"

    var id: String { rawValue }

    var ratioValue: CGFloat? {
        switch self {
        case .off: nil
        case .scope239: 2.39
        case .cinema185: 1.85
        case .wide169: 16.0 / 9.0
        case .classic43: 4.0 / 3.0
        case .square11: 1.0
        case .vertical916: 9.0 / 16.0
        }
    }
}

/// Anamorphic de-squeeze factors
enum AnamorphicFactor: String, CaseIterable, Identifiable, Sendable {
    case spherical = "1.0x (Esférico)"
    case factor133 = "1.33x Anamórfico"
    case factor155 = "1.55x Anamórfico"
    case factor180 = "1.80x Anamórfico"

    var id: String { rawValue }

    var scaleFactor: CGFloat {
        switch self {
        case .spherical: 1.0
        case .factor133: 1.33
        case .factor155: 1.55
        case .factor180: 1.80
        }
    }
}

/// Cinematic color grading LUT preview simulation
enum CineColorGrade: String, CaseIterable, Identifiable, Sendable {
    case standard = "Natural Rec.709"
    case appleLog = "Apple Log"
    case tealOrange = "Teal & Orange"
    case cineNoir = "Monochrome Noir"
    case warmGold = "Golden Hour"
    case cyberNeon = "Cyber Neon"
    case technicolor = "Technicolor 1950"

    var id: String { rawValue }
}

/// Focus Peaking Color
enum FocusPeakingColor: String, CaseIterable, Identifiable, Sendable {
    case green = "Verde Neón"
    case cyan = "Cian Eléctrico"
    case magenta = "Magenta"

    var id: String { rawValue }

    var swiftUIColor: Color {
        switch self {
        case .green: .green
        case .cyan: .cyan
        case .magenta: .pink
        }
    }
}

/// Shutter Angle options
enum ShutterAngle: String, CaseIterable, Identifiable, Sendable {
    case angle45 = "45°"
    case angle90 = "90°"
    case angle180 = "180° Cine"
    case angle270 = "270°"
    case angle360 = "360°"
    case custom = "Manual"

    var id: String { rawValue }

    var angleDegrees: Double? {
        switch self {
        case .angle45: 45.0
        case .angle90: 90.0
        case .angle180: 180.0
        case .angle270: 270.0
        case .angle360: 360.0
        case .custom: nil
        }
    }
}

/// Physical or virtual lens selection
enum CineLens: String, CaseIterable, Identifiable, Sendable {
    case ultraWide = "0.5x (13mm)"
    case wide = "1x (24mm)"
    case twoX = "2x (48mm)"
    case telephoto = "5x (120mm)"

    var id: String { rawValue }

    var zoomFactor: CGFloat {
        switch self {
        case .ultraWide: 0.5
        case .wide: 1.0
        case .twoX: 2.0
        case .telephoto: 5.0
        }
    }
}

/// Advanced manual and automatic video recording engine
@MainActor
@Observable
final class ProVideoEngine: NSObject, AVCaptureFileOutputRecordingDelegate {
    private static let logger = Logger(subsystem: "com.vileroccietti.Fusion", category: "provideo")

    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let cameraQueue = DispatchQueue(label: "com.vileroccietti.Fusion.videoQueue")

    private(set) var activeDevice: AVCaptureDevice?
    private(set) var isRunning = false
    private(set) var isRecording = false

    // Camera Operational Mode: Auto (Point-and-shoot) vs Pro Cine
    var isProMode: Bool = false {
        didSet { applyOperationalMode() }
    }

    // Video Resolution & Frame Rate
    var targetResolution4K: Bool = true {
        didSet { configureSessionPreset() }
    }

    /// Customizable frame rate (FPS). Standard cine presets: 24, 25, 30, 48, 50, 60, 120, or custom arbitrary FPS
    var currentFPS: Int = 60 {
        didSet { applyFrameRate() }
    }

    // Shutter Angle / Exposure Mode
    var isAutoExposure: Bool = true {
        didSet { applyExposure() }
    }
    var selectedShutterAngle: ShutterAngle = .angle180 {
        didSet { applyExposure() }
    }
    var manualISO: Float = 100 {
        didSet { applyExposure() }
    }
    var manualShutter: Double = 1.0 / 120.0 {
        didSet { applyExposure() }
    }
    var exposureBias: Float = 0.0 {
        didSet { applyExposureBias() }
    }

    // White Balance
    var isAutoWB: Bool = true {
        didSet { applyWhiteBalance() }
    }
    var currentKelvin: Int = 5600 {
        didSet { applyWhiteBalance() }
    }
    var currentTint: Float = 0.0 {
        didSet { applyWhiteBalance() }
    }

    // Focus & Rack Focus
    var isAutoFocus: Bool = true {
        didSet { applyFocus() }
    }
    var manualFocus: Float = 0.5 {
        didSet { applyFocus() }
    }
    var rackFocusPointA: Float? = nil
    var rackFocusPointB: Float? = nil
    var rackFocusPointC: Float? = nil
    var rackFocusDuration: Double = 1.2

    // Focus Peaking & Assist
    var isFocusPeakingActive: Bool = false
    var focusPeakingColor: FocusPeakingColor = .green
    var isZebraActive: Bool = false
    var isFalseColorActive: Bool = false

    // Color Grade & Aspect Ratio
    var selectedColorGrade: CineColorGrade = .standard
    var selectedAspectRatio: CineAspectRatio = .off
    var selectedAnamorphic: AnamorphicFactor = .spherical

    // Optical stabilization
    var isCinematicStabilization: Bool = true {
        didSet { applyStabilization() }
    }

    // Flash / Torch
    var isTorchActive: Bool = false {
        didSet { applyTorch() }
    }

    // Lens & Zoom
    var activeLens: CineLens = .wide {
        didSet { applyLens(activeLens) }
    }
    var zoomFactor: CGFloat = 1.0 {
        didSet { applyZoom() }
    }

    // Diagnostics & Recording Metrics
    private(set) var recordedSeconds: Double = 0
    private(set) var timecodeString: String = "00:00:00:00"
    private(set) var audioLevelLeft: Float = -60.0
    private(set) var audioLevelRight: Float = -60.0
    private(set) var freeStorageGB: Double = 64.0
    private(set) var estimatedRemainingMinutes: Int = 120

    private var recordingTimer: Timer?
    private var outputFileURL: URL?

    // Last recorded video url for immediate playback
    private(set) var lastRecordedURL: URL?
    private(set) var lastThumbnail: UIImage?

    override init() {
        super.init()
    }

    // MARK: - Lifecycle

    func configure() {
        session.beginConfiguration()
        configureSessionPreset()

        // Choose triple camera or wide angle camera
        let device = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)

        guard let device else {
            session.commitConfiguration()
            return
        }
        self.activeDevice = device

        do {
            let videoInput = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            }

            if let audioDevice = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
               session.canAddInput(audioInput) {
                session.addInput(audioInput)
            }

            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
                applyStabilization()
            }

            session.commitConfiguration()
            applyFrameRate()
            applyExposure()
            applyWhiteBalance()
            calculateFreeSpace()
        } catch {
            Self.logger.error("Error al configurar ProVideoEngine: \(error.localizedDescription)")
            session.commitConfiguration()
        }
    }

    private func configureSessionPreset() {
        if targetResolution4K && session.canSetSessionPreset(.hd4K3840x2160) {
            session.sessionPreset = .hd4K3840x2160
        } else {
            session.sessionPreset = .high
        }
    }

    func start() {
        guard !session.isRunning else { return }
        let captureSession = self.session
        cameraQueue.async { [weak self] in
            captureSession.startRunning()
            Task { @MainActor in
                self?.isRunning = true
            }
        }
    }

    func stop() {
        guard session.isRunning else { return }
        if isRecording {
            stopRecording()
        }
        let captureSession = self.session
        cameraQueue.async { [weak self] in
            captureSession.stopRunning()
            Task { @MainActor in
                self?.isRunning = false
            }
        }
    }

    // MARK: - Operational Mode (Auto vs Pro)

    private func applyOperationalMode() {
        if !isProMode {
            // Auto Mode: point & shoot simplicity
            isAutoExposure = true
            isAutoFocus = true
            isAutoWB = true
            exposureBias = 0.0
            isFocusPeakingActive = false
            isZebraActive = false
            isFalseColorActive = false
            selectedColorGrade = .standard
            selectedAspectRatio = .off
            selectedAnamorphic = .spherical
        }
        applyExposure()
        applyWhiteBalance()
        applyFocus()
    }

    // MARK: - Frame Rate & Format Selection

    func setCustomFPS(_ fps: Int) {
        let clamped = max(1, min(120, fps))
        self.currentFPS = clamped
    }

    private func applyFrameRate() {
        guard let device = activeDevice else { return }
        let target = currentFPS

        do {
            try device.lockForConfiguration()

            // Find best matching format supporting target frame rate
            var bestFormat: AVCaptureDevice.Format? = nil
            for format in device.formats {
                for range in format.videoSupportedFrameRateRanges {
                    if range.maxFrameRate >= Double(target) && range.minFrameRate <= Double(target) {
                        let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                        if targetResolution4K {
                            if dims.width >= 3840 {
                                bestFormat = format
                                break
                            }
                        } else {
                            if dims.width >= 1920 {
                                bestFormat = format
                                break
                            }
                        }
                    }
                }
                if bestFormat != nil { break }
            }

            if let chosen = bestFormat {
                device.activeFormat = chosen
            }

            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, target)))
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration

            device.unlockForConfiguration()
            applyExposure()
        } catch {
            Self.logger.error("No se pudo configurar framerate \(target): \(error.localizedDescription)")
        }
    }

    // MARK: - Exposure & Shutter

    private func applyExposure() {
        guard let device = activeDevice else { return }
        do {
            try device.lockForConfiguration()
            if isAutoExposure {
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
            } else {
                let shutter: Double
                if let angleDeg = selectedShutterAngle.angleDegrees {
                    // Shutter time = (Angle / 360) * (1 / FPS)
                    shutter = (angleDeg / 360.0) * (1.0 / Double(max(1, currentFPS)))
                    self.manualShutter = shutter
                } else {
                    shutter = manualShutter
                }

                let duration = CMTime(seconds: max(0.0001, min(1.0, shutter)), preferredTimescale: 1000000)
                let iso = max(device.activeFormat.minISO, min(device.activeFormat.maxISO, manualISO))
                device.setExposureModeCustom(duration: duration, iso: iso, completionHandler: nil)
            }
            device.unlockForConfiguration()
        } catch {
            Self.logger.error("Error aplicando exposición: \(error.localizedDescription)")
        }
    }

    private func applyExposureBias() {
        guard let device = activeDevice else { return }
        do {
            try device.lockForConfiguration()
            let minBias = device.minExposureTargetBias
            let maxBias = device.maxExposureTargetBias
            let clamped = max(minBias, min(maxBias, exposureBias))
            device.setExposureTargetBias(clamped, completionHandler: nil)
            device.unlockForConfiguration()
        } catch {
            Self.logger.error("Error aplicando EV bias: \(error.localizedDescription)")
        }
    }

    // MARK: - White Balance

    private func applyWhiteBalance() {
        guard let device = activeDevice else { return }
        do {
            try device.lockForConfiguration()
            if isAutoWB {
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
            } else {
                let tempAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                    temperature: Float(currentKelvin),
                    tint: currentTint
                )
                let gains = device.deviceWhiteBalanceGains(for: tempAndTint)
                let maxGain = device.maxWhiteBalanceGain
                let clampedGains = AVCaptureDevice.WhiteBalanceGains(
                    redGain: max(1.0, min(maxGain, gains.redGain)),
                    greenGain: max(1.0, min(maxGain, gains.greenGain)),
                    blueGain: max(1.0, min(maxGain, gains.blueGain))
                )
                device.setWhiteBalanceModeLocked(with: clampedGains, completionHandler: nil)
            }
            device.unlockForConfiguration()
        } catch {
            Self.logger.error("Error aplicando balance de blancos: \(error.localizedDescription)")
        }
    }

    func setKelvinPreset(_ kelvin: Int) {
        self.isAutoWB = false
        self.currentKelvin = kelvin
        self.currentTint = 0.0
        HapticFeedback.selection()
    }

    // MARK: - Focus & Rack Focus

    private func applyFocus() {
        guard let device = activeDevice else { return }
        do {
            try device.lockForConfiguration()
            if isAutoFocus {
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
            } else {
                if device.isFocusModeSupported(.locked) {
                    device.setFocusModeLocked(lensPosition: max(0.0, min(1.0, manualFocus)), completionHandler: nil)
                }
            }
            device.unlockForConfiguration()
        } catch {
            Self.logger.error("Error aplicando enfoque: \(error.localizedDescription)")
        }
    }

    func setRackFocusPoint(point: Character) {
        switch point {
        case "A": rackFocusPointA = manualFocus
        case "B": rackFocusPointB = manualFocus
        case "C": rackFocusPointC = manualFocus
        default: break
        }
        HapticFeedback.medium()
    }

    func transitionRackFocus(toTarget: Float) {
        isAutoFocus = false
        let start = manualFocus
        let steps = 30
        let stepInterval = rackFocusDuration / Double(steps)

        for step in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepInterval * Double(step)) { [weak self] in
                guard let self else { return }
                let progress = Float(step) / Float(steps)
                self.manualFocus = start + (toTarget - start) * progress
            }
        }
        HapticFeedback.light()
    }

    func tapToFocusAndExpose(at point: CGPoint) {
        guard let device = activeDevice else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
            HapticFeedback.light()
        } catch {
            Self.logger.error("Error al enfocar por toque: \(error.localizedDescription)")
        }
    }

    // MARK: - Zoom & Lens Selection

    private func applyLens(_ lens: CineLens) {
        self.zoomFactor = lens.zoomFactor
        applyZoom()
        HapticFeedback.selection()
    }

    private func applyZoom() {
        guard let device = activeDevice else { return }
        do {
            try device.lockForConfiguration()
            let minZoom = device.minAvailableVideoZoomFactor
            let maxZoom = min(25.0, device.maxAvailableVideoZoomFactor)
            let clamped = max(minZoom, min(maxZoom, zoomFactor))
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        } catch {
            Self.logger.error("Error aplicando zoom: \(error.localizedDescription)")
        }
    }

    // MARK: - Torch & Stabilization

    private func applyTorch() {
        guard let device = activeDevice, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if isTorchActive {
                try device.setTorchModeOn(level: 1.0)
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
        } catch {
            Self.logger.error("Error aplicando antorcha: \(error.localizedDescription)")
        }
    }

    private func applyStabilization() {
        guard let connection = movieOutput.connection(with: .video) else { return }
        if connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = isCinematicStabilization ? .cinematicExtended : .off
        }
    }

    // MARK: - Recording Actions

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard !isRecording else { return }
        let tempDir = FileManager.default.temporaryDirectory
        let resTag = targetResolution4K ? "4K" : "1080p"
        let fileName = "Fusion_\(resTag)_\(currentFPS)fps_\(Int(Date().timeIntervalSince1970)).mov"
        let fileURL = tempDir.appendingPathComponent(fileName)
        self.outputFileURL = fileURL

        try? FileManager.default.removeItem(at: fileURL)

        HapticFeedback.heavy()
        movieOutput.startRecording(to: fileURL, recordingDelegate: self)
        isRecording = true
        recordedSeconds = 0

        startTimers()
    }

    func stopRecording() {
        guard isRecording else { return }
        HapticFeedback.heavy()
        movieOutput.stopRecording()
        isRecording = false
        stopTimers()
    }

    // MARK: - Timers & Meters

    private func startTimers() {
        recordingTimer?.invalidate()
        let startTime = Date()

        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let elapsed = Date().timeIntervalSince(startTime)
                self.recordedSeconds = elapsed

                let hours = Int(elapsed) / 3600
                let minutes = (Int(elapsed) % 3600) / 60
                let seconds = Int(elapsed) % 60
                let frames = Int((elapsed.truncatingRemainder(dividingBy: 1.0)) * Double(self.currentFPS))
                self.timecodeString = String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)

                // Dynamic Stereo VU Audio levels simulation
                self.audioLevelLeft = -18.0 + Float.random(in: -12...4)
                self.audioLevelRight = -19.0 + Float.random(in: -12...5)
            }
        }
    }

    private func stopTimers() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        audioLevelLeft = -60.0
        audioLevelRight = -60.0
    }

    private func calculateFreeSpace() {
        if let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let freeBytes = attributes[.systemFreeSize] as? Int64 {
            let gb = Double(freeBytes) / 1_000_000_000.0
            self.freeStorageGB = gb
            // At ~500 MB per minute of 4K60
            self.estimatedRemainingMinutes = max(1, Int(gb * 2.0))
        }
    }

    // MARK: - Delegate

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        Task { @MainActor in
            self.isRecording = false
            self.stopTimers()

            if error == nil {
                self.lastRecordedURL = outputFileURL
                self.generateThumbnail(for: outputFileURL)
                self.saveToPhotoLibrary(fileURL: outputFileURL)
                HapticFeedback.success()
            } else {
                Self.logger.error("Error durante grabación de video: \(error?.localizedDescription ?? "desconocido")")
                HapticFeedback.warning()
            }
        }
    }

    private func generateThumbnail(for url: URL) {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        if let cgImg = try? generator.copyCGImage(at: time, actualTime: nil) {
            self.lastThumbnail = UIImage(cgImage: cgImg)
        }
    }

    private func saveToPhotoLibrary(fileURL: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }
        }
    }
}
