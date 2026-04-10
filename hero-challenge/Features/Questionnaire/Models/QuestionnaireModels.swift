import Foundation

// MARK: - Questionnaire Models

/// A single question in the post-recording questionnaire.
struct QuestionnaireItem: Identifiable {
    let id: UUID
    let type: QuestionType
    let question: String
    var context: String?
    var answer: QuestionAnswer
    var unitLabel: String
    var referenceId: UUID?
    var sourceDescription: String?

    init(type: QuestionType, question: String, context: String? = nil, answer: QuestionAnswer = .unanswered, unitLabel: String = "", referenceId: UUID? = nil, sourceDescription: String? = nil) {
        self.id = UUID()
        self.type = type
        self.question = question
        self.context = context
        self.answer = answer
        self.unitLabel = unitLabel
        self.referenceId = referenceId
        self.sourceDescription = sourceDescription
    }

    enum QuestionType: String {
        case orderAssignment   // Typ 1: Auftragsnachfrage
        case billing           // Typ 3: Abrechnungsfragen
        case articleSelection  // Typ 2: Artikelnachfrage
        case freeText          // Typ 4: Freitext
        case quantityConfirmation // Typ 5: Mengenbestätigung pro Leistung/Material
        case timeframe         // Typ 6: Gewünschter Zeitraum
    }
}

enum QuestionAnswer {
    case unanswered
    case project(ProjectMatch?)
    case billingMethod(BillingMethod)
    case article(SupplyProductVersion?)
    case freeText(String)
    case quantity(Double?)        // confirmed or edited quantity
    case timeframe(String)        // desired timeframe text

    var isAnswered: Bool {
        switch self {
        case .unanswered: return false
        case .project(let p): return p != nil
        case .billingMethod(let m): return m != .unselected
        case .article(let a): return a != nil
        case .freeText(let t): return !t.isEmpty
        case .quantity(let q): return q != nil
        case .timeframe(let t): return !t.isEmpty
        }
    }
}

enum BillingMethod: Equatable {
    case unselected
    case hourly(hours: Double)
    case serviceType(SupplyService?)

    static func == (lhs: BillingMethod, rhs: BillingMethod) -> Bool {
        switch (lhs, rhs) {
        case (.unselected, .unselected): return true
        case (.hourly(let a), .hourly(let b)): return a == b
        case (.serviceType(let a), .serviceType(let b)): return a?.id == b?.id
        default: return false
        }
    }
}
