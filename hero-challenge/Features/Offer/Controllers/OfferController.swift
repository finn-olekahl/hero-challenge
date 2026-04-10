import Foundation
import Observation

/// Controller that generates a complete offer via AI, then creates it via the HERO API.
@Observable
final class OfferController {
    private(set) var isGenerating = false
    private(set) var isCreating = false
    private(set) var isCompleted = false
    private(set) var errorMessage: String?
    private(set) var createdDocumentId: Int?
    private(set) var generatedOffer: GeneratedOffer?

    private let apiService: HeroAPIService
    private let offerGenService = OfferGenerationService()
    let evaluation: AIEvaluation
    let answers: QuestionnaireController.CollectedAnswers
    let transcript: String

    var isWorking: Bool { isGenerating || isCreating }

    init(evaluation: AIEvaluation, answers: QuestionnaireController.CollectedAnswers, apiService: HeroAPIService, transcript: String = "") {
        self.evaluation = evaluation
        self.answers = answers
        self.apiService = apiService
        self.transcript = transcript
    }

    // MARK: - Generate Offer via AI

    func generateOffer() async {
        guard !isGenerating else { return }
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        do {
            let offer = try await offerGenService.generateOffer(
                evaluation: evaluation,
                answers: answers,
                transcript: transcript
            )
            generatedOffer = offer
        } catch {
            errorMessage = "KI-Generierung fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    // MARK: - Create via API

    func createOffer() async {
        guard !isCreating, let offer = generatedOffer else { return }
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }

        do {
            let actions = buildDocumentActions(from: offer)

            let documentTypes = try await apiService.fetchDocumentTypes(baseTypes: ["offer"])
            guard let offerType = documentTypes.first else {
                errorMessage = "Kein Angebots-Dokumenttyp gefunden."
                return
            }

            guard let project = answers.project else {
                errorMessage = "Kein Projekt ausgewählt."
                return
            }

            let draft = try await apiService.createDocument(
                actions: actions,
                projectMatchId: project.id,
                documentTypeId: offerType.id
            )

            createdDocumentId = draft.id
            isCompleted = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func buildDocumentActions(from offer: GeneratedOffer) -> [[String: AnyCodable]] {
        var actions: [[String: AnyCodable]] = []

        for service in offer.servicePositions {
            let serviceAction: [String: AnyCodable] = [
                "name": AnyCodable(service.name),
                "description": AnyCodable(service.description),
                "unit_type": AnyCodable(Self.sanitizeUnitType(service.unitType)),
                "net_price_per_unit": AnyCodable(service.netPricePerUnit),
                "vat_percent": AnyCodable(19.0),
                "quantity": AnyCodable(service.quantity)
            ]
            actions.append(["create_supply_service": AnyCodable(serviceAction)])
        }

        for product in offer.productPositions {
            if let catalogId = product.catalogProductId, !catalogId.isEmpty {
                let productAction: [String: AnyCodable] = [
                    "product_id": AnyCodable(catalogId),
                    "quantity": AnyCodable(product.quantity)
                ]
                actions.append(["add_product_position_by_id": AnyCodable(productAction)])
            } else {
                let productAction: [String: AnyCodable] = [
                    "name": AnyCodable(product.name),
                    "description": AnyCodable(product.description),
                    "unit_type": AnyCodable(Self.sanitizeUnitType(product.unitType)),
                    "quantity": AnyCodable(product.quantity),
                    "net_price": AnyCodable(product.netPrice),
                    "vat_percent": AnyCodable(19.0)
                ]
                actions.append(["add_product_position": AnyCodable(productAction)])
            }
        }

        return actions
    }

    /// Maps common AI-generated unit abbreviations to valid HERO API unit types.
    private static func sanitizeUnitType(_ unit: String) -> String {
        let mapping: [String: String] = [
            "psch": "pauschal",
            "pschl": "pauschal",
            "pausch": "pauschal",
            "l": "L",
            "liter": "L",
            "stk.": "Stk",
            "stück": "Stk",
            "stueck": "Stk",
            "std.": "Std",
            "stunde": "Std",
            "stunden": "Std",
            "qm": "m\u{00B2}",
            "m2": "m\u{00B2}",
            "meter": "m",
        ]
        return mapping[unit.lowercased()] ?? unit
    }

    /// Summary of what will be created.
    var offerSummary: OfferSummary {
        if let offer = generatedOffer {
            return OfferSummary(
                projectName: answers.project?.displayName ?? "—",
                serviceCount: offer.servicePositions.count,
                materialCount: offer.productPositions.count,
                title: offer.title
            )
        }
        return OfferSummary(
            projectName: answers.project?.displayName ?? "—",
            serviceCount: answers.billingMethods.count,
            materialCount: answers.selectedProducts.filter { $0.product != nil }.count,
            title: nil
        )
    }
}

struct OfferSummary {
    let projectName: String
    let serviceCount: Int
    let materialCount: Int
    let title: String?

    var totalPositions: Int { serviceCount + materialCount }
}
