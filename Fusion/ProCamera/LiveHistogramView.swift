import SwiftUI

/// Compact real-time luminance and RGB histogram visualizer for professional exposure evaluation
struct LiveHistogramView: View {
    let bins: [Float] // 64 or 256 normalized values 0.0 - 1.0

    var body: some View {
        Canvas { context, size in
            guard !bins.isEmpty else { return }

            let barWidth = size.width / CGFloat(bins.count)
            let maxHeight = size.height

            for (index, value) in bins.enumerated() {
                let x = CGFloat(index) * barWidth
                let height = CGFloat(min(max(value, 0), 1)) * maxHeight
                let y = maxHeight - height

                let rect = CGRect(x: x, y: y, width: max(barWidth - 0.5, 0.5), height: height)
                let color = Color.white.opacity(0.8)
                context.fill(Path(rect), with: .color(color))
            }
        }
        .frame(width: 90, height: 44)
        .padding(4)
        .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.2), lineWidth: 0.5))
    }
}
