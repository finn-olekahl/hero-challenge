import Foundation
import SceneKit
import Observation
#if os(iOS)
import UIKit
#endif

/// Controller managing AR measurement state during a recording session.
/// Unified flow: place points to create connected line segments.
/// When the crosshair is near the first point (≥3 points), tapping closes the polygon
/// and automatically calculates the enclosed area — like Apple's Measure app.
@Observable
final class MeasureController {

    #if os(iOS)
    private let hapticGenerator: UIImpactFeedbackGenerator = {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.prepare()
        return gen
    }()
    #endif

    /// Distance threshold (meters) for snapping crosshair to the first point to close a polygon.
    private let snapThreshold: Float = 0.08

    // MARK: - State

    /// Committed line segments with distance labels.
    private(set) var segments: [MeasurementSegment] = []
    /// The current chain of placed points (first point → live line to crosshair).
    private(set) var placedPoints: [MeasurementPoint] = []
    /// Finalized area polygons.
    private(set) var finalizedAreas: [AreaPolygon] = []

    var crosshairWorldPosition: SCNVector3?
    var isSurfaceDetected: Bool = false
    var surfaceNormal: SIMD3<Float> = SIMD3<Float>(0, 1, 0)
    var instructionText: String = "iPhone bewegen um Fläche zu erkennen."

    // MARK: - Computed

    /// Whether a live measurement line is being drawn from the last placed point to the crosshair.
    var isLiveMeasuring: Bool { !placedPoints.isEmpty }

    /// Whether the crosshair is close enough to the first point to close a polygon.
    var isNearFirstPoint: Bool {
        guard placedPoints.count >= 3,
              let crosshair = crosshairWorldPosition,
              let first = placedPoints.first else { return false }
        let dist = simd_distance(first.position, SIMD3<Float>(crosshair.x, crosshair.y, crosshair.z))
        return dist < snapThreshold
    }

    var canUndo: Bool { !placedPoints.isEmpty || !segments.isEmpty || !finalizedAreas.isEmpty }
    var canClear: Bool { canUndo }

    /// Live distance text from last placed point to crosshair.
    var liveDistanceText: String? {
        guard let last = placedPoints.last, let end = crosshairWorldPosition else { return nil }
        if isNearFirstPoint { return nil } // suppress when about to snap
        let d = simd_distance(last.position, SIMD3<Float>(end.x, end.y, end.z))
        if d >= 1 { return String(format: "%.2f m", d) }
        return String(format: "%.1f cm", d * 100)
    }

    /// Callback when a measurement is finalized.
    var onMeasurementCompleted: ((ARMeasurement) -> Void)?
    /// Callback when previously-reported line measurements should be removed
    /// (e.g. they were intermediate segments of a now-closed polygon).
    var onMeasurementsRevoked: (([UUID]) -> Void)?

    /// IDs of line measurements reported during the current point chain
    /// that should be revoked if the chain becomes a closed polygon.
    private var pendingLineMeasurementIDs: [UUID] = []

    // MARK: - Actions

    func addPoint() {
        guard isSurfaceDetected, let position = crosshairWorldPosition else { return }

        #if os(iOS)
        hapticGenerator.impactOccurred()
        hapticGenerator.prepare()
        #endif

        // If near the first point and enough points to form an area → close polygon
        if isNearFirstPoint {
            closePolygon()
            return
        }

        let point = MeasurementPoint(position)

        // If we already have points, create a segment from the last point to this one
        if let last = placedPoints.last {
            let segment = MeasurementSegment(start: last, end: point)
            segments.append(segment)
            instructionText = segment.formattedDistance

            let measurement = ARMeasurement(
                type: .length,
                value: Double(segment.distance),
                unit: "m"
            )
            onMeasurementCompleted?(measurement)
            pendingLineMeasurementIDs.append(measurement.id)
        } else {
            instructionText = "Nächsten Punkt setzen."
        }

        placedPoints.append(point)
    }

    private func closePolygon() {
        guard placedPoints.count >= 3 else { return }

        // Revoke intermediate line measurements — only the area matters
        if !pendingLineMeasurementIDs.isEmpty {
            onMeasurementsRevoked?(pendingLineMeasurementIDs)
            pendingLineMeasurementIDs.removeAll()
        }

        // Add the closing segment (last → first)
        let closingSegment = MeasurementSegment(start: placedPoints.last!, end: placedPoints.first!)
        segments.append(closingSegment)

        // Calculate & store area
        let area = calculatePolygonArea(placedPoints)
        let polygon = AreaPolygon(points: placedPoints, area: area)
        finalizedAreas.append(polygon)

        let measurement = ARMeasurement(
            type: .area,
            value: area,
            unit: "m²"
        )
        onMeasurementCompleted?(measurement)

        instructionText = String(format: "Fläche: %.2f m²", area)
        placedPoints.removeAll()

        #if os(iOS)
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        heavy.impactOccurred()
        #endif
    }

    func undo() {
        if !placedPoints.isEmpty {
            placedPoints.removeLast()
            // Also remove the last segment that was created with this point
            if !segments.isEmpty && !placedPoints.isEmpty {
                segments.removeLast()
            }
            if placedPoints.isEmpty {
                instructionText = "Punkt setzen zum Messen."
            } else {
                instructionText = "Nächsten Punkt setzen."
            }
            return
        }

        if !finalizedAreas.isEmpty {
            let polygon = finalizedAreas.removeLast()
            // Remove segments that belong to this polygon (count = polygon.points.count)
            let segmentsToRemove = polygon.points.count
            if segments.count >= segmentsToRemove {
                segments.removeLast(segmentsToRemove)
            }
            instructionText = "Fläche rückgängig gemacht."
            return
        }

        if !segments.isEmpty {
            segments.removeLast()
            instructionText = segments.last?.formattedDistance ?? "Punkt setzen zum Messen."
        }
    }

    func clear() {
        segments.removeAll()
        placedPoints.removeAll()
        finalizedAreas.removeAll()
        instructionText = "iPhone bewegen um Fläche zu erkennen."
    }

    // MARK: - Area Calculation

    private func calculatePolygonArea(_ points: [MeasurementPoint]) -> Double {
        guard points.count >= 3 else { return 0 }

        // Use Newell's method for 3D polygon area
        var normal = SIMD3<Float>(0, 0, 0)
        let n = points.count
        for i in 0..<n {
            let current = points[i].position
            let next = points[(i + 1) % n].position
            normal.x += (current.y - next.y) * (current.z + next.z)
            normal.y += (current.z - next.z) * (current.x + next.x)
            normal.z += (current.x - next.x) * (current.y + next.y)
        }

        return Double(simd_length(normal)) / 2.0
    }
}
