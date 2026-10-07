import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// Edge detection focus peaking shader for manual focus assist
final class FocusPeakingFilter {
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let edgesFilter = CIFilter.edges()

    /// Applies high-pass edge filter and tints sharp high-frequency edges
    func processFrame(_ image: CIImage, peakingColor: UIColor = .systemGreen) -> CIImage? {
        edgesFilter.inputImage = image
        edgesFilter.intensity = 2.5

        guard let edgeOutput = edgesFilter.outputImage else { return nil }

        // Mask with tint color
        let colorOutput = CIImage(color: CIColor(color: peakingColor))

        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = colorOutput
        blendFilter.backgroundImage = CIImage.clear
        blendFilter.maskImage = edgeOutput

        return blendFilter.outputImage
    }
}
