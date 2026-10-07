import Foundation
import RoomPlan
import simd

/// Summary of classified room entities and physical bounds
struct RoomSummary: Sendable {
    let walls: Int
    let doors: Int
    let windows: Int
    let openings: Int
    let objects: Int

    /// Metric dimensions in millimeters [width, height, depth]
    let dimensionsMillimetres: [Int]?

    init(room: CapturedRoom) {
        walls = room.walls.count
        doors = room.doors.count
        windows = room.windows.count
        openings = room.openings.count
        objects = room.objects.count

        var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        var sawCorner = false

        for surface in room.walls + room.floors {
            let half = surface.dimensions / 2
            for x in [-half.x, half.x] {
                for y in [-half.y, half.y] {
                    let world = surface.transform * SIMD4<Float>(x, y, 0, 1)
                    let point = SIMD3<Float>(world.x, world.y, world.z)
                    minimum = simd_min(minimum, point)
                    maximum = simd_max(maximum, point)
                    sawCorner = true
                }
            }
        }

        guard sawCorner else {
            dimensionsMillimetres = nil
            return
        }
        let extent = maximum - minimum
        dimensionsMillimetres = [extent.x, extent.y, extent.z].map { Int(($0 * 1000).rounded()) }
    }

    var text: String {
        var parts: [String] = ["\(walls) paredes"]
        if doors > 0 { parts.append("\(doors) puertas") }
        if windows > 0 { parts.append("\(windows) ventanas") }
        if openings > 0 { parts.append("\(openings) accesos") }
        if objects > 0 { parts.append("\(objects) muebles") }
        return parts.joined(separator: " · ")
    }
}
