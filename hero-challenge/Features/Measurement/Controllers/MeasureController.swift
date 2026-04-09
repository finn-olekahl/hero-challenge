import Foundation
import SceneKit
import Observation
#if os(iOS)
import UIKit
#endif

/// Measurement modes available during recording.
enum MeasureMode {
    case length
    case area
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

    // MARK: - State

    private(set) var segments: [MeasurementSegment] = []
    private(set) var currentStartPoint: MeasurementPoint?
    var crosshairWorldPosition: SCNVector3?
    var isSurfaceDetected: Bool = false
    var surfaceNormal: SIMD3<Float> = SIMD3<Float>(0, 1, 0)
    var instructionText: String = "iPhone bewegen um Fläche zu erkennen."
    var mode: MeasureMode = .length

    /// Area points for polygon-based area measurement.
    private(set) var areaPoints: [MeasurementPoint] = []

    // MARK: - Computed

    var isLiveMeasuring: Bool { currentStartPoint != nil }
    var canUndo: Bool { currentStartPoint != nil || !segments.isEmpty || !areaPoints.isEmpty }
    var canClear: Bool { currentStartPoint != nil || !segments.isEmpty || !areaPoints.isEmpty }

    var liveDistanceText: String? {
        guard let start = currentStartPoint, let end = crosshairWorldPosition else { return nil }
        let d = simd_distance(start.position, SIMD3<Float>(end.x, end.y, end.z))
        if d >= 1 { return String(format: "%.2f m", d) }
        return String(format: "%.1f cm", d * 100)
    }

    /// Callback when a measurement is finalized.
    var onMeasurementCompleted: ((ARMeasurement) -> Void)?

    // MARK: - Actions

    func addPoint() {
        guard isSurfaceDetected, let position = crosshairWorldPosition else { return }
        let point = MeasurementPoint(position)

        #if os(iOS)
        hapticGenerator.impactOccurred()
        hapticGenerator.prepare()
        #endif

        switch mode {
        case .length:
            addLengthPoint(point)
        case .area:
            addAreaPoint(point)
        }
    }

    private func addLengthPoint(_ point: MeasurementPoint) {
        if let start = currentStartPoint {
            let segment = MeasurementSegment(start: start, end: point)
            segments.append(segment)
            currentStartPoint = point
            instructionText = segment.formattedDistance

            let measurement = ARMeasurement(
                type: .length,
                value: Double(segment.distance),
                unit: "m"
            )
            onMeasurementCompleted?(measurement)
        } else {
            currentStartPoint = point
            instructionText = "Tippe + für den Endpunkt."
        }
    }

    private func addAreaPoint(_ point: MeasurementPoint) {
        areaPoints.append(point)

        if areaPoints.count >= 3 {
            // Show running area calculation
            let area = calculatePolygonArea(areaPoints)
            instructionText = String(format: "Fläche: %.2f m² — Tippe ✓ zum Abschließen", area)
        } else {
            instructionText = "Mindestens 3 Punkte für Flächenmessung setzen."
        }
    }

    func finalizeArea() {
        guard areaPoints.count >= 3 else { return }
        let area = calculatePolygonArea(areaPoints)

        let measurement = ARMeasurement(
            type: .area,
            value: area,
            unit: "m²"
        )
        onMeasurementCompleted?(measurement)

        instructionText = String(format: "Fläche: %.2f m²", area)
        areaPoints.removeAll()
    }

    func undo() {
        if mode == .area && !areaPoints.isEmpty {
            areaPoints.removeLast()
            if areaPoints.count >= 3 {
                let area = calculatePolygonArea(areaPoints)
                instructionText = String(format: "Fläche: %.2f m²", area)
            } else {
                instructionText = "Mindestens 3 Punkte für Flächenmessung setzen."
            }
            return
        }

        if currentStartPoint != nil && segments.isEmpty {
            currentStartPoint = nil
            instructionText = "iPhone bewegen um Fläche zu erkennen."
        } else if let last = segments.popLast() {
            currentStartPoint = last.start
            instructionText = "Tippe + für den Endpunkt."
        }
    }

    func clear() {
        segments.removeAll()
        currentStartPoint = nil
        areaPoints.removeAll()
        instructionText = "iPhone bewegen um Fläche zu erkennen."
    }

    // MARK: - Area Calculation

    private func calculatePolygonArea(_ points: [MeasurementPoint]) -> Double {
        guard points.count >= 3 else { return 0 }

        // Use Newell's method for 3D polygon area (correct for non-convex polygons)
        // Compute the signed area normal vector
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
