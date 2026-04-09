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

    private func buildDocumentActions() -> [[String: AnyCodable]] {
        var actions: [[String: AnyCodable]] = []

        // Add services — either as existing supply_service or as ad-hoc create_supply_service
        for billing in answers.billingMethods {
            switch billing.method {
            case .hourly(let hours):
                // Create an ad-hoc service position for hourly billing
                var serviceAction: [String: AnyCodable] = [
                    "name": AnyCodable(billing.service.name),
                    "unit_type": AnyCodable("Std"),
                    "net_price_per_unit": AnyCodable(0),
                    "vat_percent": AnyCodable(19.0),
                    "quantity": AnyCodable(max(hours, 1))
                ]
                if !billing.service.description.isEmpty {
                    serviceAction["description"] = AnyCodable(billing.service.description)
                }
                actions.append(["create_supply_service": AnyCodable(serviceAction)])

            case .serviceType(let supplyService):
                if let supplyService {
                    // Add an existing supply service from the catalog
                    var serviceAction: [String: AnyCodable] = [
                        "supplyServiceId": AnyCodable(supplyService.id)
                    ]
                    if let qty = billing.service.suggestedQuantity, qty > 0 {
                        serviceAction["quantity"] = AnyCodable(qty)
                    }
                    actions.append(["add_existing_service": AnyCodable(serviceAction)])
                } else {
                    // No specific service selected — create ad-hoc
                    var serviceAction: [String: AnyCodable] = [
                        "name": AnyCodable(billing.service.name),
                        "unit_type": AnyCodable(billing.service.suggestedUnit ?? "Stk"),
                        "net_price_per_unit": AnyCodable(0),
                        "vat_percent": AnyCodable(19.0),
                        "quantity": AnyCodable(billing.service.suggestedQuantity ?? 1.0)
                    ]
                    if !billing.service.description.isEmpty {
                        serviceAction["description"] = AnyCodable(billing.service.description)
                    }
                    actions.append(["create_supply_service": AnyCodable(serviceAction)])
                }

            case .unselected:
                // Create ad-hoc with defaults
                var serviceAction: [String: AnyCodable] = [
                    "name": AnyCodable(billing.service.name),
                    "unit_type": AnyCodable(billing.service.suggestedUnit ?? "Stk"),
                    "net_price_per_unit": AnyCodable(0),
                    "vat_percent": AnyCodable(19.0),
                    "quantity": AnyCodable(billing.service.suggestedQuantity ?? 1.0)
                ]
                if !billing.service.description.isEmpty {
                    serviceAction["description"] = AnyCodable(billing.service.description)
                }
                actions.append(["create_supply_service": AnyCodable(serviceAction)])
            }
        }

        // Add product positions for selected products
        for productEntry in answers.selectedProducts {
            if let product = productEntry.product, let productId = product.product_id {
                // Add product by its catalog ID
                let productAction: [String: AnyCodable] = [
                    "product_id": AnyCodable(productId),
                    "quantity": AnyCodable(productEntry.material.suggestedQuantity ?? 1.0)
                ]
                actions.append(["add_product_position_by_id": AnyCodable(productAction)])
            } else if let product = productEntry.product {
                // Add product as a manual position
                let productAction: [String: AnyCodable] = [
                    "name": AnyCodable(product.displayName),
                    "description": AnyCodable(productEntry.material.description),
                    "unit_type": AnyCodable(product.unit ?? productEntry.material.suggestedUnit ?? "Stk"),
                    "quantity": AnyCodable(productEntry.material.suggestedQuantity ?? 1.0),
                    "net_price": AnyCodable(product.price_net ?? 0),
                    "vat_percent": AnyCodable(product.vat_percent ?? 19.0)
                ]
                actions.append(["add_product_position": AnyCodable(productAction)])
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
