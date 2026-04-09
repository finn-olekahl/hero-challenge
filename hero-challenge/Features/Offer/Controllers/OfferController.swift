import Foundation
import Observation

/// Controller that creates the final offer via the HERO API.
@Observable
final class OfferController {
    private(set) var isCreating = false
    private(set) var isCompleted = false
    private(set) var errorMessage: String?
    private(set) var createdDocumentId: Int?

    private let apiService: HeroAPIService
    let evaluation: AIEvaluation
    let answers: QuestionnaireController.CollectedAnswers

    init(evaluation: AIEvaluation, answers: QuestionnaireController.CollectedAnswers, apiService: HeroAPIService) {
        self.evaluation = evaluation
        self.answers = answers
        self.apiService = apiService
    }

    func createOffer() async {
        guard !isCreating else { return }
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }

        do {
            let actions = buildDocumentActions()

            let documentTypes = try await apiService.fetchDocumentTypes(baseTypes: ["offer"])
            guard let offerType = documentTypes.first else {
                errorMessage = "Kein Angebots-Dokumenttyp gefunden."
                return
            }

            guard let project = answers.project else {
                errorMessage = "Kein Auftrag ausgewählt."
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

    private func buildDocumentActions() -> [[String: AnyCodable]] {
        var actions: [[String: AnyCodable]] = []

        // Add position for each service + selected product
        for (index, billing) in answers.billingMethods.enumerated() {
            var action: [String: AnyCodable] = [
                "type": AnyCodable("add_position"),
                "position": AnyCodable(index + 1),
                "name": AnyCodable(billing.service.name),
                "description": AnyCodable(billing.service.description)
            ]

            // Set quantity from measurement or billing
            switch billing.method {
            case .hourly(let hours):
                action["quantity"] = AnyCodable(hours)
                action["unit"] = AnyCodable("Std.")
            case .serviceType(let service):
                if let qty = billing.service.suggestedQuantity {
                    action["quantity"] = AnyCodable(qty)
                }
                action["unit"] = AnyCodable(service?.unit ?? billing.service.suggestedUnit ?? "Stk")
                if let service, let price = service.price_net {
                    action["unit_price"] = AnyCodable(price)
                }
            case .unselected:
                if let qty = billing.service.suggestedQuantity {
                    action["quantity"] = AnyCodable(qty)
                }
            }

            actions.append(action)
        }

        // Add positions for selected products
        for (index, productEntry) in answers.selectedProducts.enumerated() {
            if let product = productEntry.product {
                var action: [String: AnyCodable] = [
                    "type": AnyCodable("add_position"),
                    "position": AnyCodable(answers.billingMethods.count + index + 1),
                    "name": AnyCodable(product.displayName),
                    "description": AnyCodable(productEntry.material.description)
                ]

                if let price = product.price_net {
                    action["unit_price"] = AnyCodable(price)
                }
                if let qty = productEntry.material.suggestedQuantity {
                    action["quantity"] = AnyCodable(qty)
                }
                action["unit"] = AnyCodable(product.unit ?? productEntry.material.suggestedUnit ?? "Stk")

                actions.append(action)
            }
        }

        return actions
    }

    /// Summary of what will be created.
    var offerSummary: OfferSummary {
        OfferSummary(
            projectName: answers.project?.displayName ?? "—",
            serviceCount: answers.billingMethods.count,
            materialCount: answers.selectedProducts.filter { $0.product != nil }.count,
            freeTextCount: answers.freeTextAnswers.filter { !$0.answer.isEmpty }.count
        )
    }
}

struct OfferSummary {
    let projectName: String
    let serviceCount: Int
    let materialCount: Int
    let freeTextCount: Int

    var totalPositions: Int { serviceCount + materialCount }
}
