import Foundation
import Observation
import FoundationModels

/// Controller that builds and manages the questionnaire from the AI evaluation.
@Observable
final class QuestionnaireController {
    private(set) var items: [QuestionnaireItem] = []
    private(set) var currentIndex: Int = 0
    private(set) var isLoading: Bool = false
    private(set) var isAutoMatching: Bool = false

    // API data for dropdowns
    private(set) var projects: [ProjectMatch] = []
    private(set) var products: [SupplyProductVersion] = []
    private(set) var services: [SupplyService] = []

    private let apiService: HeroAPIService
    private let matchingService = FoundationMatchingService()
    let evaluation: AIEvaluation
    let transcript: String

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

    init(evaluation: AIEvaluation, apiService: HeroAPIService, transcript: String = "") {
        self.evaluation = evaluation
        self.apiService = apiService
        self.transcript = transcript
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
        print("📋 [Questionnaire] Built \(items.count) items: \(items.map { "\($0.type.rawValue)" }.joined(separator: ", "))")
        print("📋 [Questionnaire] Open questions from evaluation: \(evaluation.openQuestions.count)")
    }

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

        // Fetch independently — one failure must not block the others
        async let projectsTask = apiService.fetchProjects()
        async let productsTask = apiService.fetchSupplyProducts()
        async let servicesTask = apiService.fetchSupplyServices()

        do { projects = try await projectsTask } catch { print("⚠️ Failed to load projects: \(error)") }
        do { products = try await productsTask } catch { print("⚠️ Failed to load products: \(error)") }
        do { services = try await servicesTask } catch { print("⚠️ Failed to load services: \(error)") }

        isLoading = false

        // Run auto-matching with Foundation Models in the background
        await autoMatchSuggestions()
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

    // MARK: - Auto-Matching with Foundation Models

    private func autoMatchSuggestions() async {
        print("🤖 [AutoMatch] Starting auto-matching...")
        print("🤖 [AutoMatch] SystemLanguageModel available: \(SystemLanguageModel.default.isAvailable)")
        guard SystemLanguageModel.default.isAvailable else {
            print("🤖 [AutoMatch] ⛔ SystemLanguageModel not available — skipping")
            return
        }
        isAutoMatching = true
        defer {
            isAutoMatching = false
            print("🤖 [AutoMatch] Finished auto-matching")
        }

        // Auto-match project
        let suggestedName = evaluation.context?.suggestedProjectName
        let customerName = evaluation.context?.customerName
        print("🤖 [AutoMatch] Project — suggestedName: \(suggestedName ?? "nil"), customerName: \(customerName ?? "nil"), candidates: \(projects.count)")

        if let suggestedName, !projects.isEmpty {
            if let match = await matchingService.matchProject(
                suggestedName: suggestedName,
                customerName: customerName,
                candidates: projects
            ) {
                print("🤖 [AutoMatch] ✅ Project matched: \"\(match.displayName)\" (id: \(match.id))")
                if let idx = items.firstIndex(where: { $0.type == .orderAssignment }),
                   !items[idx].answer.isAnswered {
                    items[idx].answer = .project(match)
                    print("🤖 [AutoMatch] ✅ Project pre-filled at item index \(idx)")
                } else {
                    print("🤖 [AutoMatch] ⚠️ Project matched but item already answered or not found")
                }
            } else {
                print("🤖 [AutoMatch] ❌ No project match found")
            }
        } else {
            print("🤖 [AutoMatch] ⏭️ Skipping project match (no name or no candidates)")
        }

        // Auto-match products for each article question
        print("🤖 [AutoMatch] Products — materials: \(evaluation.materials.count), product candidates: \(products.count)")
        var materialIdx = 0
        for (i, item) in items.enumerated() {
            guard item.type == .articleSelection, materialIdx < evaluation.materials.count else {
                if item.type == .articleSelection { materialIdx += 1 }
                continue
            }
            let material = evaluation.materials[materialIdx]
            materialIdx += 1

            print("🤖 [AutoMatch] Article[\(materialIdx-1)] — category: \"\(material.category)\", desc: \"\(material.description)\"")

            guard !item.answer.isAnswered else {
                print("🤖 [AutoMatch] ⏭️ Article[\(materialIdx-1)] already answered — skipping")
                continue
            }

            if let match = await matchingService.matchProduct(
                category: material.category,
                description: material.description,
                candidates: products,
                transcript: transcript
            ) {
                items[i].answer = .article(match)
                print("🤖 [AutoMatch] ✅ Article[\(materialIdx-1)] matched: \"\(match.displayName)\" at item index \(i)")
            } else {
                print("🤖 [AutoMatch] ❌ Article[\(materialIdx-1)] no match found")
            }
        }
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
