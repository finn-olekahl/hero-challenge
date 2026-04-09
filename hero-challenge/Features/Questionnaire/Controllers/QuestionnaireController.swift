import Foundation
import Observation

/// Controller that builds and manages the questionnaire from the AI evaluation.
@Observable
final class QuestionnaireController {
    private(set) var items: [QuestionnaireItem] = []
    private(set) var currentIndex: Int = 0
    private(set) var isLoading: Bool = false

    // API data for dropdowns
    private(set) var projects: [ProjectMatch] = []
    private(set) var products: [SupplyProductVersion] = []
    private(set) var services: [SupplyService] = []

    private let apiService: HeroAPIService
    let evaluation: AIEvaluation

    var currentItem: QuestionnaireItem? {
        guard currentIndex < items.count else { return nil }
        return items[currentIndex]
    }

    var isCompleted: Bool {
        currentIndex >= items.count && !items.isEmpty
    }

    var progress: Double {
        guard !items.isEmpty else { return 0 }
        return Double(currentIndex) / Double(items.count)
    }

    var answeredCount: Int {
        items.filter { $0.answer.isAnswered }.count
    }

    init(evaluation: AIEvaluation, apiService: HeroAPIService) {
        self.evaluation = evaluation
        self.apiService = apiService
        buildQuestionnaire()
    }

    // MARK: - Build Questionnaire (ordered per spec: 1 → 3 → 2 → 4)

    private func buildQuestionnaire() {
        var questions: [QuestionnaireItem] = []

        // Typ 1: Auftragsnachfrage (always first)
        let orderQuestion = QuestionnaireItem(
            type: .orderAssignment,
            question: "Welchem Projekt gehört dieses Angebot?",
            context: evaluation.context?.suggestedProjectName ?? evaluation.context?.customerName,
            answer: .project(nil)
        )
        questions.append(orderQuestion)

        // Typ 3: Abrechnungsfragen (for each service)
        for service in evaluation.services {
            let billingQuestion = QuestionnaireItem(
                type: .billing,
                question: "Abrechnung für: \(service.name)",
                context: service.description,
                answer: .billingMethod(.unselected)
            )
            questions.append(billingQuestion)
        }

        // Typ 2: Artikelnachfrage (for each material)
        for material in evaluation.materials {
            let quantityStr = material.suggestedQuantity.map { String(format: "%.1f %@", $0, material.suggestedUnit ?? "") } ?? ""
            let articleQuestion = QuestionnaireItem(
                type: .articleSelection,
                question: "Produkt wählen: \(material.category)",
                context: "\(material.description)\(quantityStr.isEmpty ? "" : " — \(quantityStr)")",
                answer: .article(nil)
            )
            questions.append(articleQuestion)
        }

        // Typ 4: Freitext (for open questions)
        for openQ in evaluation.openQuestions {
            let freeTextQuestion = QuestionnaireItem(
                type: .freeText,
                question: openQ.question,
                context: openQ.context,
                answer: .freeText("")
            )
            questions.append(freeTextQuestion)
        }

        items = questions
    }

    // MARK: - Navigation

    func goToNext() {
        guard currentIndex < items.count else { return }
        currentIndex += 1
    }

    func goToPrevious() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }

    // MARK: - Answering

    func updateAnswer(_ answer: QuestionAnswer) {
        guard currentIndex < items.count else { return }
        items[currentIndex].answer = answer
    }

    func selectProject(_ project: ProjectMatch) {
        updateAnswer(.project(project))
    }

    func setBillingMethod(_ method: BillingMethod) {
        updateAnswer(.billingMethod(method))
    }

    func selectArticle(_ product: SupplyProductVersion) {
        updateAnswer(.article(product))
    }

    func setFreeText(_ text: String) {
        updateAnswer(.freeText(text))
    }

    // MARK: - API Loading

    func loadDropdownData() async {
        isLoading = true
        defer { isLoading = false }

        // Fetch independently — one failure must not block the others
        async let projectsTask = apiService.fetchProjects()
        async let productsTask = apiService.fetchSupplyProducts()
        async let servicesTask = apiService.fetchSupplyServices()

        do { projects = try await projectsTask } catch { print("⚠️ Failed to load projects: \(error)") }
        do { products = try await productsTask } catch { print("⚠️ Failed to load products: \(error)") }
        do { services = try await servicesTask } catch { print("⚠️ Failed to load services: \(error)") }
    }

    func searchProjects(_ query: String) async {
        guard !query.isEmpty else {
            return
        }
        do {
            projects = try await apiService.fetchProjects(search: query)
        } catch { }
    }

    func searchProducts(_ query: String) async {
        guard !query.isEmpty else { return }
        do {
            products = try await apiService.fetchSupplyProducts(search: query)
        } catch { }
    }

    // MARK: - Collect Answers

    var selectedProject: ProjectMatch? {
        for item in items where item.type == .orderAssignment {
            if case .project(let p) = item.answer { return p }
        }
        return nil
    }

    struct CollectedAnswers {
        let project: ProjectMatch?
        let billingMethods: [(service: IdentifiedService, method: BillingMethod)]
        let selectedProducts: [(material: IdentifiedMaterial, product: SupplyProductVersion?)]
        let freeTextAnswers: [(question: String, answer: String)]
    }

    func collectAnswers() -> CollectedAnswers {
        var project: ProjectMatch?
        var billing: [(IdentifiedService, BillingMethod)] = []
        var products: [(IdentifiedMaterial, SupplyProductVersion?)] = []
        var freeTexts: [(String, String)] = []

        var serviceIdx = 0
        var materialIdx = 0

        for item in items {
            switch item.type {
            case .orderAssignment:
                if case .project(let p) = item.answer { project = p }
            case .billing:
                if serviceIdx < evaluation.services.count {
                    if case .billingMethod(let m) = item.answer {
                        billing.append((evaluation.services[serviceIdx], m))
                    }
                    serviceIdx += 1
                }
            case .articleSelection:
                if materialIdx < evaluation.materials.count {
                    if case .article(let a) = item.answer {
                        products.append((evaluation.materials[materialIdx], a))
                    }
                    materialIdx += 1
                }
            case .freeText:
                if case .freeText(let t) = item.answer {
                    freeTexts.append((item.question, t))
                }
            }
        }

        return CollectedAnswers(project: project, billingMethods: billing, selectedProducts: products, freeTextAnswers: freeTexts)
    }
}
