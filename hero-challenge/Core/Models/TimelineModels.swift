import Foundation
import UIKit

// MARK: - Timeline

/// The central data structure that captures everything during a recording session.
/// Each entry has a type, content, and timestamp relative to the recording start.
struct RecordingTimeline: Codable {
    var entries: [TimelineEntry] = []
    let startedAt: Date

    init(startedAt: Date = Date()) {
        self.startedAt = startedAt
    }

    mutating func addTranscript(_ text: String, at timestamp: TimeInterval) {
        // Replace the last transcript entry instead of appending duplicates.
        // Apple Speech sends cumulative partial results — we only need the latest.
        if let lastIndex = entries.lastIndex(where: { $0.type == .transcript }) {
            entries[lastIndex] = TimelineEntry(
                type: .transcript,
                timestamp: timestamp,
                content: .transcript(text)
            )
        } else {
            entries.append(TimelineEntry(
                type: .transcript,
                timestamp: timestamp,
                content: .transcript(text)
            ))
        }
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
        case transcript
        case photo
        case measurement
    }

    enum EntryContent: Codable {
        case transcript(String)
        case photo(UUID)
        case measurement(ARMeasurement)

        var transcriptText: String? {
            if case .transcript(let text) = self { return text }
            return nil
        }

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
