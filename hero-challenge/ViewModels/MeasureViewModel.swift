//
//  MeasureViewModel.swift
//  hero-challenge
//

import Foundation
import SceneKit
import Observation
#if os(iOS)
import UIKit
#endif

/// Central state for the Measure-app clone.
@Observable
final class MeasureViewModel {

    // MARK: - Haptic (pre-created to avoid first-use hitch)

    #if os(iOS)
    private let hapticGenerator: UIImpactFeedbackGenerator = {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.prepare()
        return gen
    }()
    #endif

    // MARK: - Published State

    /// Completed measurement segments.
    private(set) var segments: [MeasurementSegment] = []

    /// The start point of a measurement currently in progress.
    private(set) var currentStartPoint: MeasurementPoint?

    /// Current crosshair world position (updated every frame by the AR coordinator).
    var crosshairWorldPosition: SCNVector3?

    /// Whether the crosshair is currently hitting a real-world surface.
    var isSurfaceDetected: Bool = false

    /// The normal of the detected surface – used to orient the crosshair indicator.
    var surfaceNormal: SIMD3<Float> = SIMD3<Float>(0, 1, 0)

    /// Instruction text shown at the top of the screen.
    var instructionText: String = "Move iPhone to start measuring."

    // MARK: - Computed

    var isLiveMeasuring: Bool { currentStartPoint != nil }

    var canUndo: Bool { currentStartPoint != nil || !segments.isEmpty }

    var canClear: Bool { currentStartPoint != nil || !segments.isEmpty }

    /// Live distance string shown while measuring.
    var liveDistanceText: String? {
        guard let start = currentStartPoint, let end = crosshairWorldPosition else { return nil }
        let d = simd_distance(start.position, SIMD3<Float>(end.x, end.y, end.z))
        if d >= 1 { return String(format: "%.2f m", d) }
        return String(format: "%.1f cm", d * 100)
    }

    // MARK: - Actions

    /// Place (or finalise) a measurement point at the current crosshair position.
    func addPoint() {
        guard isSurfaceDetected, let position = crosshairWorldPosition else { return }

        let point = MeasurementPoint(position)

        // Haptic
        #if os(iOS)
        hapticGenerator.impactOccurred()
        hapticGenerator.prepare()   // re-arm for next tap
        #endif

        if let start = currentStartPoint {
            // Finalise segment
            let segment = MeasurementSegment(start: start, end: point)
            segments.append(segment)
            // Chain: start next measurement from end point
            currentStartPoint = point
            instructionText = segment.formattedDistance
        } else {
            // First point
            currentStartPoint = point
            instructionText = "Tap + to set the end point."
        }
    }

    /// Undo the last action (remove start point or pop last segment).
    func undo() {
        if currentStartPoint != nil && segments.isEmpty {
            currentStartPoint = nil
            instructionText = "Move iPhone to start measuring."
        } else if currentStartPoint != nil {
            // We are chaining — go back to the last segment's start
            currentStartPoint = segments.last?.end != nil ? nil : nil
            if let last = segments.popLast() {
                currentStartPoint = last.start
                instructionText = "Tap + to set the end point."
            }
        } else if let last = segments.popLast() {
            currentStartPoint = last.start
            instructionText = "Tap + to set the end point."
        }
    }

    /// Clear all measurements.
    func clear() {
        segments.removeAll()
        currentStartPoint = nil
        instructionText = "Move iPhone to start measuring."
    }
}
