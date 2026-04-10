import Foundation
import SceneKit

// MARK: - Distance Formatting

/// Formats a distance in meters to a human-readable string (e.g. "1.25 m" or "42.3 cm").
func formattedDistance(_ meters: Float) -> String {
    if meters >= 1 {
        return String(format: "%.2f m", meters)
    } else {
        return String(format: "%.1f cm", meters * 100)
    }
}

/// A point placed in 3-D world space during measurement.
struct MeasurementPoint: Equatable, Codable {
    let position: SIMD3<Float>

    var scnVector3: SCNVector3 {
        SCNVector3(position.x, position.y, position.z)
    }

    init(position: SIMD3<Float>) {
        self.position = position
    }

    init(_ v: SCNVector3) {
        self.position = SIMD3<Float>(v.x, v.y, v.z)
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case x, y, z
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try container.decode(Float.self, forKey: .x)
        let y = try container.decode(Float.self, forKey: .y)
        let z = try container.decode(Float.self, forKey: .z)
        self.position = SIMD3<Float>(x, y, z)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(position.x, forKey: .x)
        try container.encode(position.y, forKey: .y)
        try container.encode(position.z, forKey: .z)
    }
}

/// A finalised measurement between two world-space points.
struct MeasurementSegment: Identifiable, Equatable {
    let id = UUID()
    let start: MeasurementPoint
    let end: MeasurementPoint

    var distance: Float {
        simd_distance(start.position, end.position)
    }

    var formattedDistance: String {
        formattedDistance(distance)
    }

    var midpoint: SCNVector3 {
        let mid = (start.position + end.position) / 2
        return SCNVector3(mid.x, mid.y + 0.01, mid.z)
    }

    static func == (lhs: MeasurementSegment, rhs: MeasurementSegment) -> Bool {
        lhs.id == rhs.id
    }
}

/// A finalized area polygon from connected measurement points.
struct AreaPolygon: Identifiable, Equatable {
    let id = UUID()
    let points: [MeasurementPoint]
    let area: Double

    var formattedArea: String {
        String(format: "%.2f m²", area)
    }

    var centroid: SCNVector3 {
        let sum = points.reduce(SIMD3<Float>(0, 0, 0)) { $0 + $1.position }
        let avg = sum / Float(points.count)
        return SCNVector3(avg.x, avg.y + 0.015, avg.z)
    }

    static func == (lhs: AreaPolygon, rhs: AreaPolygon) -> Bool {
        lhs.id == rhs.id
    }
}
