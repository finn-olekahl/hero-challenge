import SwiftUI

/// The post-recording questionnaire that walks through all open questions.
struct QuestionnaireView: View {
    var controller: QuestionnaireController
    var onComplete: (QuestionnaireController.CollectedAnswers) -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress bar
                progressBar

                if controller.isCompleted {
                    completionView
                } else if let item = controller.currentItem {
                    questionContent(item)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Fragebogen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", action: onCancel)
                }
            }
            .onChange(of: controller.currentIndex) { _, _ in
                syncLocalState()
            }
        }
    }

    // MARK: - Local State Sync

    private func syncLocalState() {
        billingIsHourly = true
        hourCount = ""
        productSearchText = ""
        freeTextAnswer = ""
        quantityText = ""
        timeframeText = ""

        guard let item = controller.currentItem else { return }
        switch item.answer {
        case .billingMethod(let method):
            switch method {
            case .hourly(let hours):
                billingIsHourly = true
                hourCount = hours > 0 ? String(format: "%.1f", hours) : ""
            case .serviceType:
                billingIsHourly = false
            case .unselected:
                break
            }
        case .freeText(let text):
            freeTextAnswer = text
        case .quantity(let q):
            if let q {
                quantityText = String(format: "%.1f", q)
            }
        case .timeframe(let t):
            timeframeText = t
        default:
            break
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(spacing: 4) {
            ProgressView(value: controller.progress)
                .tint(.blue)

            HStack {
                Text("Frage \(min(controller.currentIndex + 1, controller.items.count)) von \(controller.items.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(controller.answeredCount) beantwortet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Question Content

    @ViewBuilder
    private func questionContent(_ item: QuestionnaireItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Question header
                VStack(alignment: .leading, spacing: 8) {
                    questionTypeBadge(item.type)

                    Text(item.question)
                        .font(.title2.weight(.semibold))

                    if let context = item.context, !context.isEmpty {
                        Text(context)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Answer input
                answerInput(item)
            }
            .padding()
        }

        // Navigation buttons
        navigationButtons
    }

    @ViewBuilder
    private func questionTypeBadge(_ type: QuestionnaireItem.QuestionType) -> some View {
        let (label, color): (String, Color) = switch type {
        case .orderAssignment: ("Projekt", .blue)
        case .billing: ("Abrechnung", .orange)
        case .articleSelection: ("Artikel", .green)
        case .freeText: ("Freitext", .purple)
        case .quantityConfirmation: ("Menge", .teal)
        case .timeframe: ("Zeitraum", .indigo)
        }

        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - Answer Inputs

    @ViewBuilder
    private func answerInput(_ item: QuestionnaireItem) -> some View {
        switch item.type {
        case .orderAssignment:
            orderAssignmentInput

        case .billing:
            billingInput

        case .articleSelection:
            articleSelectionInput

        case .freeText:
            freeTextInput

        case .quantityConfirmation:
            quantityConfirmationInput

        case .timeframe:
            timeframeInput
        }
    }

    // MARK: Order Assignment

    private var orderAssignmentInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Projekt auswählen")
                .font(.subheadline.weight(.medium))

            if case .project(let p) = controller.currentItem?.answer, p != nil {
                Label("Automatisch ausgewählt – tippe um zu ändern", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

            if controller.isLoading {
                ProgressView("Lade Projekte...")
            }

            ForEach(sortedProjects) { project in
                Button {
                    controller.selectProject(project)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.displayName)
                                .font(.body.weight(.medium))
                            if let customer = project.customer {
                                Text(customer.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if case .project(let selected) = controller.currentItem?.answer,
                           selected?.id == project.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding()
                    .background {
                        if case .project(let selected) = controller.currentItem?.answer,
                           selected?.id == project.id {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.blue.opacity(0.08))
                        } else {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.secondarySystemBackground))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Billing

    @State private var billingIsHourly = true
    @State private var hourCount: String = ""

    private var billingInput: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Toggle: Stunden vs Leistungstyp
            Picker("Abrechnungsart", selection: $billingIsHourly) {
                Text("Nach Stunden").tag(true)
                Text("Nach Leistungstyp").tag(false)
            }
            .pickerStyle(.segmented)
            .onChange(of: billingIsHourly) { _, isHourly in
                if isHourly {
                    let hours = Double(hourCount.replacingOccurrences(of: ",", with: ".")) ?? 0
                    controller.setBillingMethod(.hourly(hours: hours))
                } else {
                    controller.setBillingMethod(.serviceType(nil))
                }
            }

            if billingIsHourly {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Anzahl Stunden")
                        .font(.subheadline.weight(.medium))
                    TextField("z.B. 4,5", text: $hourCount)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Leistungstyp auswählen")
                        .font(.subheadline.weight(.medium))

                    ForEach(controller.services) { service in
                        Button {
                            controller.setBillingMethod(.serviceType(service))
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(service.displayName)
                                        .font(.body)
                                    if let price = service.net_price_per_unit {
                                        Text(String(format: "%.2f € / %@", price, service.unit_type ?? "Stk"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if case .billingMethod(.serviceType(let selected)) = controller.currentItem?.answer,
                                   selected?.id == service.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Article Selection

    @State private var productSearchText = ""

    private var articleSelectionInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Produkt auswählen")
                .font(.subheadline.weight(.medium))

            if case .article(let a) = controller.currentItem?.answer, a != nil {
                Label("Automatisch ausgewählt – tippe um zu ändern", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

            TextField("Suchen...", text: $productSearchText)
                .textFieldStyle(.roundedBorder)
                .onChange(of: productSearchText) { _, newValue in
                    Task {
                        await controller.searchProducts(newValue)
                    }
                }

            if controller.isLoading {
                ProgressView("Lade Produkte...")
            }

            ForEach(sortedProducts) { product in
                Button {
                    controller.selectArticle(product)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.displayName)
                                .font(.body)
                            if let price = product.price_net {
                                Text(String(format: "%.2f € / %@", price, product.unit ?? "Stk"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if case .article(let selected) = controller.currentItem?.answer,
                           selected?.id == product.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding()
                    .background {
                        if case .article(let selected) = controller.currentItem?.answer,
                           selected?.id == product.id {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.blue.opacity(0.08))
                        } else {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.secondarySystemBackground))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Free Text

    @State private var freeTextAnswer = ""

    private var freeTextInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ihre Antwort")
                .font(.subheadline.weight(.medium))

            TextEditor(text: $freeTextAnswer)
                .frame(minHeight: 120)
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: Quantity Confirmation

    @State private var quantityText = ""

    private var quantityConfirmationInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Menge prüfen und ggf. anpassen")
                .font(.subheadline.weight(.medium))

            HStack(spacing: 12) {
                TextField("Menge", text: $quantityText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)

                if let item = controller.currentItem, !item.unitLabel.isEmpty {
                    Text(item.unitLabel)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.blue)
                }

                Spacer()
            }

            // Source info: where did this value come from?
            if let item = controller.currentItem, let source = item.sourceDescription, !source.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: Timeframe

    @State private var timeframeText = ""

    private var timeframeInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gewünschter Zeitraum")
                .font(.subheadline.weight(.medium))

            TextField("z.B. nächste Woche, ab Mai, so schnell wie möglich", text: $timeframeText)
                .textFieldStyle(.roundedBorder)

            Text("Der Zeitraum wird im Dokument als Hinweis vermerkt.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Sorted Lists (auto-selected on top)

    private var sortedProjects: [ProjectMatch] {
        guard case .project(let selected) = controller.currentItem?.answer,
              let selected else { return controller.projects }
        var sorted = controller.projects
        if let idx = sorted.firstIndex(where: { $0.id == selected.id }), idx > 0 {
            let item = sorted.remove(at: idx)
            sorted.insert(item, at: 0)
        }
        return sorted
    }

    private var sortedProducts: [SupplyProductVersion] {
        guard case .article(let selected) = controller.currentItem?.answer,
              let selected else { return controller.products }
        var sorted = controller.products
        if let idx = sorted.firstIndex(where: { $0.id == selected.id }), idx > 0 {
            let item = sorted.remove(at: idx)
            sorted.insert(item, at: 0)
        }
        return sorted
    }

    // MARK: - Navigation Buttons

    /// Flush local @State values to the controller before navigating away.
    private func commitLocalState() {
        guard let item = controller.currentItem else { return }
        switch item.type {
        case .billing:
            if billingIsHourly {
                let hours = Double(hourCount.replacingOccurrences(of: ",", with: ".")) ?? 0
                controller.setBillingMethod(.hourly(hours: hours))
            }
        case .freeText:
            controller.setFreeText(freeTextAnswer)
        case .quantityConfirmation:
            let qty = Double(quantityText.replacingOccurrences(of: ",", with: "."))
            controller.setQuantity(qty)
        case .timeframe:
            controller.setTimeframe(timeframeText)
        default:
            break
        }
    }

    private var navigationButtons: some View {
        HStack {
            if controller.currentIndex > 0 {
                Button {
                    commitLocalState()
                    controller.goToPrevious()
                } label: {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Zurück")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            Button {
                commitLocalState()
                controller.goToNext()
            } label: {
                HStack {
                    Text(controller.currentIndex == controller.items.count - 1 ? "Abschließen" : "Weiter")
                    Image(systemName: "chevron.right")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundStyle(.white)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
    }

    // MARK: - Completion

    private var completionView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("Fragebogen abgeschlossen")
                .font(.title2.weight(.semibold))

            Text("\(controller.answeredCount) von \(controller.items.count) Fragen beantwortet")
                .foregroundStyle(.secondary)

            Button {
                let answers = controller.collectAnswers()
                onComplete(answers)
            } label: {
                Text(completionButtonLabel)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundStyle(.white)
                    .background(intentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Intent-Aware Labels

    private var completionButtonLabel: String {
        switch controller.evaluation.intent {
        case .offer: return "Angebot erstellen"
        case .workReport: return "Arbeitsbericht erstellen"
        case .siteReport: return "Baustellenbericht erstellen"
        }
    }

    private var intentColor: Color {
        switch controller.evaluation.intent {
        case .offer: return .blue
        case .workReport, .siteReport: return .teal
        }
    }
}
