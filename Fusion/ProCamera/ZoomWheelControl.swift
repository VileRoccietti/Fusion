import SwiftUI
import UIKit

/// Interactive tactile zoom wheel control with physical focal length markings and haptics
struct ZoomWheelControl: View {
    @Binding var zoomFactor: CGFloat
    var minZoom: CGFloat = 0.5
    var maxZoom: CGFloat = 25.0

    @State private var isDragging = false
    @State private var dragOffset: CGFloat = 0

    // Key optical presets for iPhone 16 Pro Max
    struct LensPreset: Identifiable {
        let id: String
        let factor: CGFloat
        let focalMm: String
        let label: String
    }

    private let presets: [LensPreset] = [
        LensPreset(id: "uw", factor: 0.5, focalMm: "13mm", label: ".5"),
        LensPreset(id: "wide", factor: 1.0, focalMm: "24mm", label: "1x"),
        LensPreset(id: "crop28", factor: 1.2, focalMm: "28mm", label: "1.2"),
        LensPreset(id: "crop35", factor: 1.5, focalMm: "35mm", label: "1.5"),
        LensPreset(id: "fusion", factor: 2.0, focalMm: "48mm", label: "2x"),
        LensPreset(id: "tele", factor: 5.0, focalMm: "120mm", label: "5x")
    ]

    var body: some View {
        VStack(spacing: 10) {
            // Optical quick presets
            HStack(spacing: 12) {
                ForEach(presets) { preset in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            zoomFactor = preset.factor
                        }
                        HapticFeedback.selection()
                    } label: {
                        Text(preset.label)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .frame(width: 38, height: 38)
                            .background(
                                Circle()
                                    .fill(abs(zoomFactor - preset.factor) < 0.1 ? Color.yellow : Color.black.opacity(0.6))
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                            .foregroundStyle(abs(zoomFactor - preset.factor) < 0.1 ? Color.black : Color.white)
                    }
                }
            }

            // Radial tactile arc dial
            dialScroller
                .frame(height: 48)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var dialScroller: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let midX = width / 2

            ZStack {
                // Background track
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )

                // Graduation tick marks
                HStack(spacing: 7) {
                    ForEach(0..<60) { tick in
                        let factor = tickToFactor(tick)
                        let isMajor = isMajorTick(factor)

                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(isMajor ? Color.yellow : Color.white.opacity(0.35))
                                .frame(width: isMajor ? 2 : 1, height: isMajor ? 18 : 10)

                            if isMajor && tick % 10 == 0 {
                                Text(String(format: "%.1fx", factor))
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.yellow)
                                    .padding(.top, 2)
                            }
                        }
                    }
                }
                .offset(x: -factorToOffset(zoomFactor, totalWidth: width) + dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                HapticFeedback.selection()
                            }
                            dragOffset = value.translation.width
                            let delta = -value.translation.width * 0.02
                            let newZoom = max(minZoom, min(maxZoom, zoomFactor + delta))
                            if abs(newZoom - zoomFactor) > 0.05 {
                                zoomFactor = newZoom
                                HapticFeedback.selection()
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                dragOffset = 0
                                isDragging = false
                                snapToNearestOptical()
                            }
                        }
                )

                // Center indicator needle
                VStack(spacing: 2) {
                    Rectangle()
                        .fill(Color.yellow)
                        .frame(width: 2.5, height: 26)
                        .shadow(color: .yellow.opacity(0.6), radius: 3)

                    Text(String(format: "%.1f×", zoomFactor))
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(Color.yellow)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.75), in: Capsule())
                }
                .position(x: midX, y: 24)
            }
        }
    }

    private func tickToFactor(_ tick: Int) -> CGFloat {
        if tick < 10 {
            return 0.5 + CGFloat(tick) * 0.05
        } else if tick < 25 {
            return 1.0 + CGFloat(tick - 10) * 0.1
        } else if tick < 40 {
            return 2.5 + CGFloat(tick - 25) * 0.2
        } else {
            return 5.5 + CGFloat(tick - 40) * 1.0
        }
    }

    private func isMajorTick(_ factor: CGFloat) -> Bool {
        for preset in presets {
            if abs(factor - preset.factor) < 0.08 { return true }
        }
        return false
    }

    private func factorToOffset(_ factor: CGFloat, totalWidth: CGFloat) -> CGFloat {
        let normalized = (factor - minZoom) / (maxZoom - minZoom)
        return (normalized - 0.5) * totalWidth * 1.5
    }

    private func snapToNearestOptical() {
        for preset in presets {
            if abs(zoomFactor - preset.factor) < 0.15 {
                zoomFactor = preset.factor
                HapticFeedback.light()
                break
            }
        }
    }
}
