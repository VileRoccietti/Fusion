import AVFoundation
import os

/// AVCaptureSession coordinator for tripod turntable scanning
final class PhotoCaptureCoordinator: NSObject, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.vileroccietti.Fusion", category: "turntable")

    enum SetupError: LocalizedError {
        case noCamera
        case configurationFailed(String)
        case noPhotoData

        var errorDescription: String? {
            switch self {
            case .noCamera: "No se encontró la cámara trasera."
            case .configurationFailed(let detail): "No se pudo configurar la cámara: \(detail)"
            case .noPhotoData: "No se recibieron datos de la foto."
            }
        }
    }

    let session = AVCaptureSession()
    private(set) var deliversDepth = false
    private(set) var megapixels = 0

    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.vileroccietti.Fusion.turntable")
    private let imagesDirectory: URL

    private var device: AVCaptureDevice?
    private var maxDimensions = CMVideoDimensions(width: 0, height: 0)

    private var pendingCaptures: [Int64: PhotoDelegate] = [:]
    private let pendingLock = NSLock()

    private var shotIndex = 0
    private var bestSharpness: Float = 0
    private let sharpnessFloor: Float = 0.45

    private let onShotSaved: @Sendable (Int) -> Void
    private let onShotRejected: @Sendable (String) -> Void
    private let onFailure: @Sendable (String) -> Void

    init(
        imagesDirectory: URL,
        onShotSaved: @escaping @Sendable (Int) -> Void,
        onShotRejected: @escaping @Sendable (String) -> Void,
        onFailure: @escaping @Sendable (String) -> Void
    ) {
        self.imagesDirectory = imagesDirectory
        self.onShotSaved = onShotSaved
        self.onShotRejected = onShotRejected
        self.onFailure = onFailure
        super.init()
    }

    func configure() throws {
        let device = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)

        guard let device else { throw SetupError.noCamera }
        self.device = device

        session.beginConfiguration()
        session.sessionPreset = .photo

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                throw SetupError.configurationFailed("No se pudo añadir la entrada de cámara.")
            }
            session.addInput(input)
        } catch let error as SetupError {
            session.commitConfiguration()
            throw error
        } catch {
            session.commitConfiguration()
            throw SetupError.configurationFailed(error.localizedDescription)
        }

        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            throw SetupError.configurationFailed("No se pudo añadir la salida fotográfica.")
        }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality

        if let largest = device.activeFormat.supportedMaxPhotoDimensions
            .max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }) {
            maxDimensions = largest
            photoOutput.maxPhotoDimensions = largest
            megapixels = Int((Double(largest.width) * Double(largest.height) / 1_000_000).rounded())
        }

        if photoOutput.isDepthDataDeliverySupported {
            photoOutput.isDepthDataDeliveryEnabled = true
            deliversDepth = true
        }

        session.commitConfiguration()

        if let connection = photoOutput.connection(with: .video), connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .off
        }

        Self.logger.info("Cámara de mesa giratoria lista — \(self.megapixels, privacy: .public) MP, profundidad LiDAR: \(self.deliversDepth, privacy: .public)")
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func lockCameraSettings(completion: @escaping @Sendable (Bool) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.device else {
                completion(false)
                return
            }

            do {
                try device.lockForConfiguration()
            } catch {
                completion(false)
                return
            }

            let centre = CGPoint(x: 0.5, y: 0.5)
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = centre }
            if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }
            if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = centre }
            if device.isExposureModeSupported(.autoExpose) { device.exposureMode = .autoExpose }
            if device.isWhiteBalanceModeSupported(.autoWhiteBalance) {
                device.whiteBalanceMode = .autoWhiteBalance
            }
            device.unlockForConfiguration()

            for _ in 0..<40 where device.isAdjustingFocus || device.isAdjustingExposure || device.isAdjustingWhiteBalance {
                Thread.sleep(forTimeInterval: 0.05)
            }

            guard (try? device.lockForConfiguration()) != nil else {
                completion(false)
                return
            }
            if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
            if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
            if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
            device.unlockForConfiguration()

            Self.logger.info("Enfoque, exposición y balance de blancos fijados")
            completion(true)
        }
    }

    func capture() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }

            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else {
                settings = AVCapturePhotoSettings()
            }

            if self.maxDimensions.width > 0 {
                settings.maxPhotoDimensions = self.maxDimensions
            }
            settings.photoQualityPrioritization = .quality

            if self.photoOutput.isDepthDataDeliveryEnabled {
                settings.isDepthDataDeliveryEnabled = true
                settings.embedsDepthDataInPhoto = true
            }

            if let previewFormat = settings.availablePreviewPhotoPixelFormatTypes.first {
                settings.previewPhotoFormat = [
                    kCVPixelBufferPixelFormatTypeKey as String: previewFormat,
                    kCVPixelBufferWidthKey as String: 512,
                    kCVPixelBufferHeightKey as String: 384,
                ]
            }

            self.shotIndex += 1
            let index = self.shotIndex
            let destination = self.imagesDirectory
                .appending(path: String(format: "shot_%04d.heic", index), directoryHint: .notDirectory)

            let settingsID = settings.uniqueID

            let delegate = PhotoDelegate(destination: destination) { [weak self] result in
                guard let self else { return }
                self.pendingLock.lock()
                self.pendingCaptures[settingsID] = nil
                self.pendingLock.unlock()
                self.handle(result: result, index: index, destination: destination)
            }

            self.pendingLock.lock()
            self.pendingCaptures[settingsID] = delegate
            self.pendingLock.unlock()

            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    private func handle(result: Result<PhotoDelegate.Capture, Error>, index: Int, destination: URL) {
        switch result {
        case .failure(let error):
            onFailure(error.localizedDescription)

        case .success(let capture):
            guard let sharpness = capture.sharpness else {
                onShotSaved(index)
                return
            }

            bestSharpness = max(bestSharpness, sharpness)

            if sharpness < bestSharpness * sharpnessFloor {
                try? FileManager.default.removeItem(at: destination)
                shotIndex -= 1
                Self.logger.debug("Foto borrosa descartada: \(sharpness, privacy: .public)")
                onShotRejected("Foto descartada por desenfoque de movimiento — gira más despacio")
            } else {
                onShotSaved(index)
            }
        }
    }
}

private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    struct Capture {
        var sharpness: Float?
    }

    private let destination: URL
    private let completion: @Sendable (Result<Capture, Error>) -> Void

    init(destination: URL, completion: @escaping @Sendable (Result<Capture, Error>) -> Void) {
        self.destination = destination
        self.completion = completion
        super.init()
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            completion(.failure(error))
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            completion(.failure(PhotoCaptureCoordinator.SetupError.noPhotoData))
            return
        }

        let sharpness = photo.previewPixelBuffer.flatMap(SharpnessMeter.score)

        do {
            try data.write(to: destination, options: .atomic)
            completion(.success(Capture(sharpness: sharpness)))
        } catch {
            completion(.failure(error))
        }
    }
}
