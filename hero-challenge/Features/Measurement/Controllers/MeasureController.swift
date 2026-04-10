import Foundation
import SceneKit
import Observation
#if os(iOS)
import UIKit
#endif

// MARK: - Measurement Mode

/// Whether the user is measuring a distance (2 points) or an area (polygon).
enum MeasurementMode: String {
    case distance
    case area
}

/// Phase of the current measurement within Messen mode.
enum MeasurePhase {
    /// User needs to pick distance or area.
    case choosingType
    /// Actively placing points.
    case measuring
    /// Current measurement finished — user can start another.
    case completed
}

/// Controller managing AR measurement state during a recording session.
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

    private(set) var measurementMode: MeasurementMode?
    private(set) var phase: MeasurePhase = .choosingType

    /// Committed line segments with distance labels.
    private(set) var segments: [MeasurementSegment] = []
    /// The current chain of placed points (first point → live line to crosshair).
    private(set) var placedPoints: [MeasurementPoint] = []
    /// Finalized area polygons.
    private(set) var finalizedAreas: [AreaPolygon] = []

    /// Result text shown after a measurement completes.
    private(set) var completedResultText: String?

    var crosshairWorldPosition: SCNVector3?
    var isSurfaceDetected: Bool = false
    var surfaceNormal: SIMD3<Float> = SIMD3<Float>(0, 1, 0)
    var instructionText: String = "iPhone bewegen um Fläche zu erkennen."

    // MARK: - Computed

    /// Whether a live measurement line is being drawn from the last placed point to the crosshair.
    var isLiveMeasuring: Bool { !placedPoints.isEmpty }

    /// Whether the crosshair is close enough to the first point to close a polygon.
    var isNearFirstPoint: Bool {
        guard measurementMode == .area,
              placedPoints.count >= 3,
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
        if isNearFirstPoint { return nil }
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

    // MARK: - Mode Selection

    /// Called when user picks distance or area from the type picker.
    func selectMode(_ mode: MeasurementMode) {
        measurementMode = mode
        phase = .measuring
        completedResultText = nil
        instructionText = mode == .distance
            ? "Startpunkt setzen."
            : "Ersten Eckpunkt setzen."
    }

    /// Start another measurement of the same or different type.
    func startNewMeasurement() {
        phase = .choosingType
        measurementMode = nil
        completedResultText = nil
        placedPoints.removeAll()
        pendingLineMeasurementIDs.removeAll()
        instructionText = "Messtyp wählen."
    }

    // MARK: - Actions

    func addPoint() {
        guard phase == .measuring,
              isSurfaceDetected,
              let position = crosshairWorldPosition else { return }

        #if os(iOS)
        hapticGenerator.impactOccurred()
        hapticGenerator.prepare()
        #endif

        // Area mode: if near the first point and enough points → close polygon
        if measurementMode == .area && isNearFirstPoint {
            closePolygon()
            return
        }

        let point = MeasurementPoint(position)

        if let last = placedPoints.last {
            let segment = MeasurementSegment(start: last, end: point)
            segments.append(segment)
            instructionText = segment.formattedDistance

            if measurementMode == .distance {
                let measurement = ARMeasurement(
                    type: .length,
                    value: Double(segment.distance),
                    unit: "m"
                )
                onMeasurementCompleted?(measurement)
                placedPoints.append(point)
                completedResultText = segment.formattedDistance
                phase = .completed

                #if os(iOS)
                let heavy = UIImpactFeedbackGenerator(style: .medium)
                heavy.impactOccurred()
                #endif
                return
            }

            let measurement = ARMeasurement(
                type: .length,
                value: Double(segment.distance),
                unit: "m"
            )
            onMeasurementCompleted?(measurement)
            pendingLineMeasurementIDs.append(measurement.id)
        } else {
            instructionText = measurementMode == .distance
                ? "Endpunkt setzen."
                : "Nächsten Eckpunkt setzen."
        }

        placedPoints.append(point)
    }

    private func closePolygon() {
        guard placedPoints.count >= 3 else { return }

        if !pendingLineMeasurementIDs.isEmpty {
            onMeasurementsRevoked?(pendingLineMeasurementIDs)
            pendingLineMeasurementIDs.removeAll()
        }

        let closingSegment = MeasurementSegment(start: placedPoints.last!, end: placedPoints.first!)
        segments.append(closingSegment)

        let area = calculatePolygonArea(placedPoints)
        let polygon = AreaPolygon(points: placedPoints, area: area)
        finalizedAreas.append(polygon)

        let measurement = ARMeasurement(
            type: .area,
            value: area,
            unit: "m²"
        )
        onMeasurementCompleted?(measurement)

        let resultText = String(format: "Fläche: %.2f m²", area)
        instructionText = resultText
        completedResultText = resultText
        phase = .completed
        placedPoints.removeAll()

        #if os(iOS)
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        heavy.impactOccurred()
        #endif
    }

    func undo() {
        if !placedPoints.isEmpty {
            placedPoints.removeLast()
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
        pendingLineMeasurementIDs.removeAll()
        measurementMode = nil
        phase = .choosingType
        completedResultText = nil
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
