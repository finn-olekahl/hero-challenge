import SwiftUI

/// Final screen: AI generates the offer, user reviews, then creates via API.
struct OfferView: View {
    var controller: OfferController
    var onDone: () -> Void

    // MARK: - Animated Generating State

    @State private var visiblePhases: Int = 0
    @State private var completedPhases: Int = 0
    @State private var showRecap: Bool = false
    @State private var pulseAnimation: Bool = false

    private let phases = [
        (icon: "text.magnifyingglass", label: "Aufnahme wird analysiert"),
        (icon: "wrench.and.screwdriver", label: "Leistungspositionen werden erstellt"),
        (icon: "shippingbox", label: "Materialpositionen werden berechnet"),
        (icon: "eurosign.circle", label: "Preise werden kalkuliert"),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if controller.generatedOffer == nil && !controller.isGenerating {
                    generatingView
                } else if controller.isGenerating {
                    generatingView
                } else if let offer = controller.generatedOffer {
                    reviewView(offer)
                }
            }
            .navigationTitle("Angebot")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            if controller.generatedOffer == nil {
                await controller.generateOffer()
            }
        }
        .onChange(of: controller.isGenerating) { _, isGenerating in
            if !isGenerating && controller.generatedOffer != nil {
                completeAllPhases()
            }
        }
    }

    // MARK: - Animated Generating View

    private var generatingView: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemBackground), Color.orange.opacity(0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 40)

                // Pulsing icon
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(Color.orange.opacity(0.15 - Double(i) * 0.04), lineWidth: 1.5)
                            .frame(width: CGFloat(80 + i * 28), height: CGFloat(80 + i * 28))
                            .scaleEffect(pulseAnimation ? 1.08 : 0.95)
                            .animation(
                                .easeInOut(duration: 1.8)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.3),
                                value: pulseAnimation
                            )
                    }

                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.orange)
                        .frame(width: 72, height: 72)
                        .background(Color.orange.opacity(0.1), in: Circle())
                }
                .padding(.bottom, 28)

                Text("KI erstellt Angebot")
                    .font(.title2.weight(.bold))
                    .padding(.bottom, 6)

                Text("Positionen, Mengen und Preise werden berechnet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 32)

                // Recap card
                if showRecap {
                    generatingRecapCard
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .padding(.horizontal, 24)
                        .padding(.bottom, 28)
                }

                // Processing phases
                VStack(spacing: 0) {
                    ForEach(Array(phases.enumerated()), id: \.offset) { index, phase in
                        if index < visiblePhases {
                            generatingPhaseRow(icon: phase.icon, label: phase.label, index: index)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                    }
                }
                .padding(.horizontal, 32)

                Spacer()
            }
        }
        .onAppear {
            pulseAnimation = true
            startGeneratingPhaseAnimations()
        }
    }

    private var generatingRecapCard: some View {
        HStack(spacing: 16) {
            generatingRecapStat(icon: "wrench.and.screwdriver", value: "\(controller.evaluation.services.count)", label: "Leistungen")
            generatingRecapDivider
            generatingRecapStat(icon: "shippingbox", value: "\(controller.evaluation.materials.count)", label: "Materialien")
            generatingRecapDivider
            generatingRecapStat(icon: "questionmark.bubble", value: "\(controller.answers.freeTextAnswers.count + controller.answers.billingMethods.count)", label: "Antworten")
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func generatingRecapStat(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.orange)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var generatingRecapDivider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: 1, height: 36)
    }

    private func generatingPhaseRow(icon: String, label: String, index: Int) -> some View {
        HStack(spacing: 14) {
            ZStack {
                if index < completedPhases {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                } else if index == completedPhases {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.orange)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                        .frame(width: 22, height: 22)
                }
            }
            .frame(width: 26, height: 26)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: completedPhases)

            Text(label)
                .font(.subheadline.weight(index <= completedPhases ? .medium : .regular))
                .foregroundStyle(index <= completedPhases ? .primary : .tertiary)

            Spacer()

            if index < completedPhases {
                Text("Fertig")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.3), value: completedPhases)
    }

    private func startGeneratingPhaseAnimations() {
        visiblePhases = 0
        completedPhases = 0
        showRecap = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showRecap = true
            }
        }

        for i in 0..<phases.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 + Double(i) * 0.4) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    visiblePhases = i + 1
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { completedPhases = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            withAnimation { completedPhases = max(completedPhases, 2) }
        }
    }

    private func completeAllPhases() {
        let remaining = phases.count - completedPhases
        for i in 0..<remaining {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.3) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    completedPhases = min(completedPhases + 1, phases.count)
                }
            }
        }
    }

    // MARK: - Review

    private func reviewView(_ offer: GeneratedOffer) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                headerSection(offer)

                // Summary card
                summaryCard

                // Service positions
                if !offer.servicePositions.isEmpty {
                    positionsSection(
                        title: "Leistungen",
                        icon: "wrench.and.screwdriver"
                    ) {
                        ForEach(offer.servicePositions) { pos in
                            serviceRow(pos)
                        }
                    }
                }

                // Product positions
                if !offer.productPositions.isEmpty {
                    positionsSection(
                        title: "Material",
                        icon: "shippingbox"
                    ) {
                        ForEach(offer.productPositions) { pos in
                            productRow(pos)
                        }
                    }
                }

                // Notes
                if let notes = offer.notes, !notes.isEmpty {
                    notesSection(notes)
                }

                // Error
                if let error = controller.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Actions
                actionButtons
            }
            .padding()
        }
    }

    private func headerSection(_ offer: GeneratedOffer) -> some View {
        VStack(spacing: 6) {
            Image(systemName: controller.isCompleted ? "checkmark.seal.fill" : "doc.text.fill")
                .font(.system(size: 44))
                .foregroundStyle(controller.isCompleted ? .green : .blue)

            Text(controller.isCompleted ? "Angebot erstellt!" : offer.title)
                .font(.title2.weight(.bold))

            if !controller.isCompleted {
                Text(offer.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 8)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Zusammenfassung")
                .font(.headline)

            summaryRow(icon: "folder", label: "Projekt", value: controller.offerSummary.projectName)
            summaryRow(icon: "wrench.and.screwdriver", label: "Leistungen", value: "\(controller.offerSummary.serviceCount)")
            summaryRow(icon: "shippingbox", label: "Material", value: "\(controller.offerSummary.materialCount)")
            summaryRow(icon: "doc.text", label: "Positionen gesamt", value: "\(controller.offerSummary.totalPositions)")
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func summaryRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body.weight(.medium))
        }
    }

    // MARK: - Position Sections

    private func positionsSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                Text(title)
                    .font(.headline)
            }

            content()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func serviceRow(_ pos: GeneratedServicePosition) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(pos.name)
                    .font(.body.weight(.medium))
                Spacer()
                Text(String(format: "%.1f %@", pos.quantity, pos.unitType))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text(pos.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if pos.netPricePerUnit > 0 {
                Text(String(format: "%.2f €/%@", pos.netPricePerUnit, pos.unitType))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 6)
    }

    private func productRow(_ pos: GeneratedProductPosition) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(pos.name)
                    .font(.body.weight(.medium))
                Spacer()
                Text(String(format: "%.1f %@", pos.quantity, pos.unitType))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text(pos.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack {
                if pos.netPrice > 0 {
                    Text(String(format: "%.2f €/%@", pos.netPrice, pos.unitType))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.blue)
                }
                if pos.catalogProductId != nil {
                    Spacer()
                    Text("Katalog")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12), in: Capsule())
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .foregroundStyle(.orange)
                Text("Hinweise")
                    .font(.headline)
            }
            Text(notes)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if controller.isCompleted {
                Button(action: onDone) {
                    Text("Fertig")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundStyle(.white)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            } else {
                Button {
                    Task { await controller.createOffer() }
                } label: {
                    if controller.isCreating {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text("Angebot in HERO anlegen")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundStyle(.white)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .disabled(controller.isWorking || controller.generatedOffer == nil)

                // Regenerate button
                Button {
                    Task { await controller.generateOffer() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Neu generieren")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.blue)
                }
                .disabled(controller.isWorking)
            }
        }
        .padding(.top, 8)
    }
}
