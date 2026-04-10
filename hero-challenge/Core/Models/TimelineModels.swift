import Foundation
import UIKit

// MARK: - Transcript Segment

/// A time-windowed chunk of transcript text.
/// Photos and measurements taken during a segment's time range can be contextually
/// associated with what was being said.
struct TranscriptSegment: Identifiable, Codable {
    let id: UUID
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String

    init(startTime: TimeInterval, endTime: TimeInterval, text: String) {
        self.id = UUID()
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
}

// MARK: - Timeline

/// The central data structure that captures everything during a recording session.
/// Transcript is stored as time-windowed segments so that photos and measurements
/// can be contextually matched to what was being said at that moment.
struct RecordingTimeline: Codable {
    var entries: [TimelineEntry] = []
    var transcriptSegments: [TranscriptSegment] = []
    let startedAt: Date

    init(startedAt: Date = Date()) {
        self.startedAt = startedAt
    }

    /// The full transcript text reconstructed from all segments.
    var fullTranscript: String {
        transcriptSegments.map(\.text).filter { !$0.isEmpty }.joined(separator: " ")
    }

    mutating func addSegments(_ segments: [TranscriptSegment]) {
        transcriptSegments.append(contentsOf: segments)
    }

    mutating func addPhoto(id: UUID, at timestamp: TimeInterval) {
        entries.append(TimelineEntry(
            type: .photo,
            timestamp: timestamp,
            content: .photo(id)
        ))
    }

    mutating func addMeasurement(_ measurement: ARMeasurement, at timestamp: TimeInterval) {
        entries.append(TimelineEntry(
            type: .measurement,
            timestamp: timestamp,
            content: .measurement(measurement)
        ))
    }

    /// Remove measurement entries whose ARMeasurement.id is in the given set.
    /// Used to revoke intermediate line segments when a polygon is closed.
    mutating func removeMeasurements(withIDs ids: Set<UUID>) {
        entries.removeAll { entry in
            guard let m = entry.content.measurementValue else { return false }
            return ids.contains(m.id)
        }
    }
}

// MARK: - Timeline Entry

struct TimelineEntry: Identifiable, Codable {
    let id: UUID
    let type: EntryType
    let timestamp: TimeInterval
    let content: EntryContent

    init(type: EntryType, timestamp: TimeInterval, content: EntryContent) {
        self.id = UUID()
        self.type = type
        self.timestamp = timestamp
        self.content = content
    }

    enum EntryType: String, Codable {
        case photo
        case measurement
    }

    enum EntryContent: Codable {
        case photo(UUID)
        case measurement(ARMeasurement)

        var photoID: UUID? {
            if case .photo(let id) = self { return id }
            return nil
        }

        var measurementValue: ARMeasurement? {
            if case .measurement(let m) = self { return m }
            return nil
        }
    }
}

// MARK: - AR Measurement

struct ARMeasurement: Codable, Identifiable {
    let id: UUID
    let type: MeasurementType
    let value: Double
    let unit: String
    let label: String

    init(type: MeasurementType, value: Double, unit: String = "m", label: String = "") {
        self.id = UUID()
        self.type = type
        self.value = value
        self.unit = unit
        self.label = label
    }

    var formattedValue: String {
        if type == .area {
            return String(format: "%.2f m²", value)
        }
        if value >= 1 {
            return String(format: "%.2f m", value)
        }
        return String(format: "%.1f cm", value * 100)
    }

    enum MeasurementType: String, Codable {
        case length
        case area
    }
}

// MARK: - Captured Photo

struct CapturedPhoto: Identifiable {
    let id: UUID
    let image: UIImage
    let timestamp: TimeInterval

    init(image: UIImage, timestamp: TimeInterval) {
        self.id = UUID()
        self.image = image
        self.timestamp = timestamp
    }
}
