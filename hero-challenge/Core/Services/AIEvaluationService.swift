import Foundation

/// Service that processes the recording timeline and produces a structured AI evaluation.
/// In production, this sends the timeline to an LLM backend.
/// For the prototype, it generates a realistic mock evaluation.
final class AIEvaluationService: Sendable {

    func evaluate(timeline: RecordingTimeline, photos: [CapturedPhoto]) async throws -> AIEvaluation {
        // Gather all transcript text
        let transcriptParts = timeline.entries
            .compactMap { $0.content.transcriptText }

        let fullTranscript = transcriptParts.joined(separator: " ")

        // Gather all measurements
        let measurements = timeline.entries
            .compactMap { $0.content.measurementValue }

        // In production: send to LLM API
        // For prototype: return structured mock based on actual data
        return buildEvaluation(
            transcript: fullTranscript,
            measurements: measurements,
            photoCount: photos.count
        )
    }

    /// Builds a realistic evaluation from the recorded data.
    /// In a production app, this would be replaced by an LLM API call.
    private func buildEvaluation(transcript: String, measurements: [ARMeasurement], photoCount: Int) -> AIEvaluation {
        var services: [IdentifiedService] = []
        var materials: [IdentifiedMaterial] = []
        var questions: [OpenQuestion] = []

        // Extract services and materials from transcript keywords
        let lowerTranscript = transcript.lowercased()

        if lowerTranscript.contains("fliese") || lowerTranscript.contains("boden") {
            let areaMeasurements = measurements.filter { $0.type == .area }
            let area = areaMeasurements.first?.value

            services.append(IdentifiedService(
                name: "Fliesenverlegung",
                description: "Boden- oder Wandfliesen verlegen",
                associatedMeasurements: areaMeasurements,
                suggestedQuantity: area,
                suggestedUnit: "m²"
            ))

            materials.append(IdentifiedMaterial(
                category: "Fliesen",
                description: "Bodenfliesen passend zum Raum",
                suggestedQuantity: area.map { $0 * 1.1 },
                suggestedUnit: "m²",
                derivedFromMeasurement: areaMeasurements.first
            ))

            materials.append(IdentifiedMaterial(
                category: "Fliesenkleber",
                description: "Flexkleber für Bodenfliesen",
                suggestedQuantity: area.map { $0 * 3.5 },
                suggestedUnit: "kg"
            ))
        }

        if lowerTranscript.contains("wand") || lowerTranscript.contains("streich") || lowerTranscript.contains("maler") {
            let areaMeasurements = measurements.filter { $0.type == .area }
            services.append(IdentifiedService(
                name: "Malerarbeiten",
                description: "Wände streichen / tapezieren",
                associatedMeasurements: areaMeasurements,
                suggestedQuantity: areaMeasurements.first?.value,
                suggestedUnit: "m²"
            ))

            materials.append(IdentifiedMaterial(
                category: "Wandfarbe",
                description: "Innenfarbe weiß",
                suggestedQuantity: areaMeasurements.first.map { $0.value * 0.15 },
                suggestedUnit: "l"
            ))
        }

        if lowerTranscript.contains("rohr") || lowerTranscript.contains("sanitär") || lowerTranscript.contains("wasser") {
            let lengthMeasurements = measurements.filter { $0.type == .length }
            services.append(IdentifiedService(
                name: "Sanitärinstallation",
                description: "Rohrverlegung und Anschlussarbeiten",
                associatedMeasurements: lengthMeasurements,
                suggestedQuantity: lengthMeasurements.first?.value,
                suggestedUnit: "m"
            ))
        }

        if lowerTranscript.contains("elektr") || lowerTranscript.contains("steckdose") || lowerTranscript.contains("licht") {
            services.append(IdentifiedService(
                name: "Elektroinstallation",
                description: "Elektroarbeiten",
                suggestedQuantity: nil,
                suggestedUnit: "Std."
            ))
        }

        // If no specific keywords found, create a generic service
        if services.isEmpty {
            services.append(IdentifiedService(
                name: "Handwerkerleistung",
                description: "Aus dem Gespräch identifizierte Leistung",
                associatedMeasurements: measurements,
                suggestedQuantity: nil,
                suggestedUnit: nil
            ))
        }

        // Always add some open questions
        questions.append(OpenQuestion(
            question: "Gibt es besondere Anforderungen an die Materialqualität?",
            context: "Keine Angaben im Gespräch gefunden"
        ))

        if measurements.isEmpty {
            questions.append(OpenQuestion(
                question: "Welche Flächen bzw. Maße sind betroffen?",
                context: "Keine Messungen während der Aufnahme durchgeführt"
            ))
        }

        // Extract order context from transcript
        let context = extractOrderContext(from: transcript)

        return AIEvaluation(
            services: services,
            materials: materials,
            context: context,
            openQuestions: questions
        )
    }

    private func extractOrderContext(from transcript: String) -> OrderContext {
        // Simple keyword extraction for prototype
        var projectName: String?
        var customerName: String?

        let words = transcript.components(separatedBy: .whitespaces)

        // Look for patterns like "Herr/Frau Name"
        for (i, word) in words.enumerated() {
            let lower = word.lowercased()
            if (lower == "herr" || lower == "frau") && i + 1 < words.count {
                customerName = "\(word) \(words[i + 1])"
            }
            if lower == "projekt" && i + 1 < words.count {
                projectName = words[i + 1]
            }
        }

        return OrderContext(
            suggestedProjectName: projectName,
            suggestedProjectId: nil,
            customerName: customerName,
            location: nil
        )
    }
}
