import Foundation

/// Saved scan metadata in local library
struct ScanRecord: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
    let engine: ScanEngineKind

    /// Relative file name inside scan folder (e.g. `model.usdz` or `cloud.ply`)
    var modelFileName: String

    /// True if scale corresponds to real-world metric units (from LiDAR or TrueDepth)
    let isMetricallyScaled: Bool

    /// Number of source photos used
    let imageCount: Int?

    /// Number of points in point cloud
    var pointCount: Int?

    /// Number of triangles in mesh
    var triangleCount: Int?

    /// Number of vertices in mesh
    var vertexCount: Int?

    /// Bounding box in mm [width, height, depth]
    var dimensionsMillimetres: [Int]?

    /// Photogrammetry detail level
    let detail: ReconstructionDetail?

    /// Text summary of contents
    var summary: String?

    /// Flag set if model has been edited in 3D Modeler (e.g. clipped, decimated)
    var isEdited: Bool?

    var isPreviewable: Bool {
        modelFileName.hasSuffix(".usdz") || modelFileName.hasSuffix(".obj")
    }

    var isPointCloud: Bool {
        modelFileName.hasSuffix(".ply")
    }

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        engine: ScanEngineKind,
        modelFileName: String = "model.usdz",
        isMetricallyScaled: Bool,
        imageCount: Int? = nil,
        pointCount: Int? = nil,
        triangleCount: Int? = nil,
        vertexCount: Int? = nil,
        dimensionsMillimetres: [Int]? = nil,
        detail: ReconstructionDetail? = nil,
        summary: String? = nil,
        isEdited: Bool? = false
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.engine = engine
        self.modelFileName = modelFileName
        self.isMetricallyScaled = isMetricallyScaled
        self.imageCount = imageCount
        self.pointCount = pointCount
        self.triangleCount = triangleCount
        self.vertexCount = vertexCount
        self.dimensionsMillimetres = dimensionsMillimetres
        self.detail = detail
        self.summary = summary
        self.isEdited = isEdited
    }
}

/// Mesh detail setting
enum ReconstructionDetail: String, Codable, CaseIterable, Sendable, Identifiable {
    case reduced

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .reduced: "Dispositivo (Optimizada)"
        }
    }

    var explanation: String {
        switch self {
        case .reduced:
            "Nivel soportado directamente en iOS. Para polígonos máximos ultra-densos, exporte el paquete de imágenes a una Mac con RealityKit CLI."
        }
    }
}
