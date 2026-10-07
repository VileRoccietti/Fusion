import Foundation
import RealityKit
import os

/// High-performance RealityKit photogrammetry reconstructor running on device
struct PhotogrammetryReconstructor {
    private static let logger = Logger(subsystem: "com.vile.ObjectScannerPro", category: "photogrammetry")

    struct Output {
        let modelURL: URL
        let poses: PoseDiagnostics?
    }

    func reconstruct(
        workspace: ScanWorkspace,
        detail: ReconstructionDetail,
        maskRect: CGRect? = nil,
        enableObjectMasking: Bool = true,
        framing: PoseDiagnostics.Framing = .orbit,
        onWarning: @escaping @MainActor (String) -> Void = { _ in },
        onProgress: @escaping @MainActor (ReconstructionProgress) -> Void
    ) async throws -> Output {

        guard PhotogrammetrySession.isSupported else {
            throw ScanEngineError.reconstructionFailed("Este dispositivo no soporta fotogrametría en el dispositivo.")
        }

        let imageURLs = ((try? FileManager.default.contentsOfDirectory(
            at: workspace.imagesURL,
            includingPropertiesForKeys: nil
        )) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let imageCount = imageURLs.count
        guard imageCount > 0 else { throw ScanEngineError.noImagesCaptured }

        var configuration = PhotogrammetrySession.Configuration(checkpointDirectory: workspace.checkpointURL)
        configuration.sampleOrdering = .sequential
        configuration.featureSensitivity = .high
        configuration.isObjectMaskingEnabled = enableObjectMasking

        try? FileManager.default.removeItem(at: workspace.modelURL)

        var effectiveMask = maskRect
        if maskRect != nil, let probe = imageURLs.first {
            do {
                _ = try await PhotogrammetrySample(contentsOf: probe)
            } catch {
                effectiveMask = nil
                Self.logger.error("No se pudo leer la muestra con máscara: \(error.localizedDescription, privacy: .public)")
                await onWarning("No se pudo aplicar la máscara de recorte: \(error.localizedDescription)")
            }
        }

        do {
            return try await run(
                workspace: workspace,
                imageURLs: imageURLs,
                imageCount: imageCount,
                detail: detail,
                maskRect: effectiveMask,
                configuration: configuration,
                framing: framing,
                onProgress: onProgress
            )
        } catch where effectiveMask != nil {
            Self.logger.error("Fallo con máscara, reintentando sin máscara")
            await onWarning("El procesamiento con máscara falló; reintentando sin máscara...")
            try? FileManager.default.removeItem(at: workspace.modelURL)
            return try await run(
                workspace: workspace,
                imageURLs: imageURLs,
                imageCount: imageCount,
                detail: detail,
                maskRect: nil,
                configuration: configuration,
                framing: framing,
                onProgress: onProgress
            )
        }
    }

    private func run(
        workspace: ScanWorkspace,
        imageURLs: [URL],
        imageCount: Int,
        detail: ReconstructionDetail,
        maskRect: CGRect?,
        configuration: PhotogrammetrySession.Configuration,
        framing: PoseDiagnostics.Framing,
        onProgress: @escaping @MainActor (ReconstructionProgress) -> Void
    ) async throws -> Output {

        let session: PhotogrammetrySession
        do {
            if let maskRect {
                session = try PhotogrammetrySession(
                    input: MaskedSampleSequence(imageURLs: imageURLs, normalizedRect: maskRect),
                    configuration: configuration
                )
            } else {
                session = try PhotogrammetrySession(input: workspace.imagesURL, configuration: configuration)
            }
        } catch {
            throw ScanEngineError.reconstructionFailed(error.localizedDescription)
        }

        let modelRequest = PhotogrammetrySession.Request.modelFile(
            url: workspace.modelURL,
            detail: detail.apiDetail
        )
        try session.process(requests: [modelRequest, .poses])

        var progress = ReconstructionProgress()
        var diagnostics: PoseDiagnostics?

        for try await output in session.outputs {
            switch output {
            case .requestProgress(let request, let fraction):
                guard request == modelRequest else { break }
                progress.fraction = fraction
                await onProgress(progress)

            case .requestProgressInfo(let request, let info):
                guard request == modelRequest else { break }
                progress.stage = info.processingStage.flatMap(ReconstructionStage.init)
                progress.estimatedRemaining = info.estimatedRemainingTime
                await onProgress(progress)

            case .requestComplete(let request, let result):
                if case .poses(let poses) = result {
                    diagnostics = PoseDiagnostics(poses: poses, totalSamples: imageCount, framing: framing)
                }
                guard request == modelRequest else { break }
                progress.fraction = 1
                await onProgress(progress)

            case .processingComplete:
                Self.logger.info("Reconstrucción completada: \(imageCount, privacy: .public) imágenes")
                return Output(modelURL: workspace.modelURL, poses: diagnostics)

            case .requestError(let request, let error):
                guard request == modelRequest else {
                    Self.logger.error("Error en petición de poses: \(error.localizedDescription, privacy: .public)")
                    break
                }
                throw ScanEngineError.reconstructionFailed(error.localizedDescription)

            case .processingCancelled:
                throw ScanEngineError.cancelled

            default:
                break
            }
        }

        guard FileManager.default.fileExists(atPath: workspace.modelURL.path(percentEncoded: false)) else {
            throw ScanEngineError.reconstructionFailed("La sesión finalizó sin generar el archivo de modelo.")
        }
        return Output(modelURL: workspace.modelURL, poses: diagnostics)
    }
}

private extension ReconstructionDetail {
    var apiDetail: PhotogrammetrySession.Request.Detail {
        switch self {
        case .reduced: .reduced
        }
    }
}

private extension ReconstructionStage {
    init?(_ stage: PhotogrammetrySession.Output.ProcessingStage) {
        switch stage {
        case .preProcessing: self = .preProcessing
        case .imageAlignment: self = .imageAlignment
        case .pointCloudGeneration: self = .pointCloudGeneration
        case .meshGeneration: self = .meshGeneration
        case .textureMapping: self = .textureMapping
        case .optimization: self = .optimization
        @unknown default: return nil
        }
    }
}
