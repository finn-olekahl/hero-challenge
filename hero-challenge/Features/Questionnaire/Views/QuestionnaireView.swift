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
            .task {
                await controller.loadDropdownData()
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
        }
    }

    // MARK: Order Assignment

    private var orderAssignmentInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Projekt auswählen")
                .font(.subheadline.weight(.medium))

            if controller.isLoading {
                ProgressView("Lade Projekte...")
            }

            ForEach(controller.projects) { project in
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
                    .background(Color(.secondarySystemBackground))
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
                        .onChange(of: hourCount) { _, newValue in
                            let hours = Double(newValue.replacingOccurrences(of: ",", with: ".")) ?? 0
                            controller.setBillingMethod(.hourly(hours: hours))
                        }
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

            ForEach(controller.products) { product in
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
                    .background(Color(.secondarySystemBackground))
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
                .onChange(of: freeTextAnswer) { _, newValue in
                    controller.setFreeText(newValue)
                }
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack {
            if controller.currentIndex > 0 {
                Button {
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
                Text("Angebot erstellen")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundStyle(.white)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }
}
