import Foundation
import SwiftUI
import UIKit

/// Kind of captured media item
enum MediaKind: String, CaseIterable, Identifiable, Sendable {
    case photo = "Fotos ProRAW"
    case video = "Videos 4K"
    case scan3D = "Modelos 3D"
    case nightVision = "Visión Nocturna"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .photo: "camera.aperture"
        case .video: "video.fill"
        case .scan3D: "cube.transparent.fill"
        case .nightVision: "moon.stars.fill"
        }
    }
}

/// Rich media record representation for the premium gallery
struct MediaItem: Identifiable, Sendable {
    let id: UUID
    let title: String
    let kind: MediaKind
    let date: Date
    let fileURL: URL
    let thumbnailURL: URL?
    let fileSizeFormatted: String

    // Technical EXIF / Camera metadata
    let resolutionText: String
    let lensText: String
    let isoText: String?
    let shutterText: String?
    let fpsText: String?
}
