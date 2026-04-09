import Foundation

// MARK: - AI Evaluation Models

/// The structured output from the AI after analyzing the recording timeline.
struct AIEvaluation: Codable {
    let services: [IdentifiedService]
    let materials: [IdentifiedMaterial]
    let context: OrderContext?
    let openQuestions: [OpenQuestion]
}

struct IdentifiedService: Codable, Identifiable {
    let id: UUID
    let name: String
    let description: String
    let associatedMeasurements: [ARMeasurement]
    let suggestedQuantity: Double?
    let suggestedUnit: String?

    init(name: String, description: String, associatedMeasurements: [ARMeasurement] = [], suggestedQuantity: Double? = nil, suggestedUnit: String? = nil) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.associatedMeasurements = associatedMeasurements
        self.suggestedQuantity = suggestedQuantity
        self.suggestedUnit = suggestedUnit
    }
}

struct IdentifiedMaterial: Codable, Identifiable {
    let id: UUID
    let category: String
    let description: String
    let suggestedQuantity: Double?
    let suggestedUnit: String?
    let derivedFromMeasurement: ARMeasurement?

    init(category: String, description: String, suggestedQuantity: Double? = nil, suggestedUnit: String? = nil, derivedFromMeasurement: ARMeasurement? = nil) {
        self.id = UUID()
        self.category = category
        self.description = description
        self.suggestedQuantity = suggestedQuantity
        self.suggestedUnit = suggestedUnit
        self.derivedFromMeasurement = derivedFromMeasurement
    }
}

struct OrderContext: Codable {
    let suggestedProjectName: String?
    let suggestedProjectId: Int?
    let customerName: String?
    let location: String?
}

struct OpenQuestion: Codable, Identifiable {
    let id: UUID
    let question: String
    let context: String?

    init(question: String, context: String? = nil) {
        self.id = UUID()
        self.question = question
        self.context = context
    }
}
