import SwiftUI

/// Final screen for work reports and site reports: AI generates the report, user reviews, then uploads via API.
struct ReportView: View {
    var controller: ReportController
    var onDone: () -> Void

    // MARK: - Animated Generating State

    @State private var visiblePhases: Int = 0
    @State private var completedPhases: Int = 0
    @State private var showRecap: Bool = false
    @State private var pulseAnimation: Bool = false

    private var phases: [(icon: String, label: String)] {
        var p = [
            (icon: "text.magnifyingglass", label: "Aufnahme wird analysiert"),
            (icon: "doc.richtext", label: "Berichtsstruktur wird erstellt"),
            (icon: "photo.on.rectangle", label: "Fotos werden zugeordnet"),
        ]
        if controller.intent == .siteReport {
            p.append((icon: "ruler", label: "Maße werden eingebettet"))
        }
        p.append((icon: "checkmark.circle", label: "Bericht wird finalisiert"))
        return p
    }

    var body: some View {
        NavigationStack {
            Group {
                if controller.generatedReport == nil && !controller.isGenerating {
                    generatingView
                } else if controller.isGenerating {
                    generatingView
                } else if controller.generatedReport != nil {
                    reviewView
                }
            }
            .navigationTitle(controller.reportTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            if controller.generatedReport == nil {
                await controller.generateReport()
            }
        }
        .onChange(of: controller.isGenerating) { _, isGenerating in
            if !isGenerating && controller.generatedReport != nil {
                completeAllPhases()
            }
        }
    }

    // MARK: - Generating View

    private var generatingView: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemBackground), Color.teal.opacity(0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 40)

                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(Color.teal.opacity(0.15 - Double(i) * 0.04), lineWidth: 1.5)
                            .frame(width: CGFloat(80 + i * 28), height: CGFloat(80 + i * 28))
                            .scaleEffect(pulseAnimation ? 1.08 : 0.95)
                            .animation(
                                .easeInOut(duration: 1.8)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.3),
                                value: pulseAnimation
                            )
                    }

                    Image(systemName: "doc.richtext")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.teal)
                        .frame(width: 72, height: 72)
                        .background(Color.teal.opacity(0.1), in: Circle())
                }
                .padding(.bottom, 28)

                Text("KI erstellt \(controller.reportTitle)")
                    .font(.title2.weight(.bold))
                    .padding(.bottom, 6)

                Text("Strukturierter Bericht wird generiert")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 32)

                if showRecap {
                    recapCard
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .padding(.horizontal, 24)
                        .padding(.bottom, 28)
                }

                VStack(spacing: 0) {
                    ForEach(Array(phases.enumerated()), id: \.offset) { index, phase in
                        if index < visiblePhases {
                            phaseRow(icon: phase.icon, label: phase.label, index: index)
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
            startPhaseAnimations()
        }
    }

    private var recapCard: some View {
        HStack(spacing: 16) {
            recapStat(icon: "wrench.and.screwdriver", value: "\(controller.evaluation.services.count)", label: "Leistungen")
            recapDivider
            recapStat(icon: "camera", value: "\(controller.photos.count)", label: "Fotos")
            recapDivider
            recapStat(icon: "doc.text", value: "\(controller.evaluation.openQuestions.count)", label: "Hinweise")
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func recapStat(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.teal)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var recapDivider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: 1, height: 36)
    }

    private func phaseRow(icon: String, label: String, index: Int) -> some View {
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
                        .tint(.teal)
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

    private func startPhaseAnimations() {
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

    // MARK: - Review View

    private var reviewView: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    // Hero header
                    reportHeader
                        .padding(.bottom, 24)

                    // Info strip
                    infoStrip
                        .padding(.horizontal)
                        .padding(.bottom, 20)

                    // Sections
                    if let report = controller.generatedReport {
                        VStack(spacing: 16) {
                            ForEach(Array(report.sections.enumerated()), id: \.offset) { index, section in
                                sectionCard(section, index: index)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Error
                    if let error = controller.errorMessage {
                        errorBanner(error)
                            .padding(.horizontal)
                            .padding(.top, 16)
                    }

                    // Extra space for the sticky button
                    Spacer().frame(height: 120)
                }
            }

            // Sticky bottom action
            stickyActionBar
        }
    }

    // MARK: - Header

    private var reportHeader: some View {
        VStack(spacing: 12) {
            if controller.isCompleted {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.green)
                    .padding(.top, 16)

                Text("\(controller.reportTitle) erstellt!")
                    .font(.title2.weight(.bold))

                Text("Der Bericht wurde erfolgreich in HERO angelegt.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            } else {
                // Accent bar
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.teal)
                    .frame(width: 40, height: 4)
                    .padding(.top, 12)

                Text(controller.generatedReport?.title ?? controller.reportTitle)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                if let summary = controller.generatedReport?.summary {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
        }
    }

    // MARK: - Info Strip

    private var infoStrip: some View {
        HStack(spacing: 0) {
            infoChip(icon: "folder.fill", label: controller.reportSummary.projectName, color: .blue)

            Spacer(minLength: 8)

            infoChip(
                icon: "doc.text.fill",
                label: "\(controller.reportSummary.sectionCount) Abschnitte",
                color: .teal
            )

            if controller.reportSummary.photoCount > 0 {
                Spacer(minLength: 8)
                infoChip(
                    icon: "camera.fill",
                    label: "\(controller.reportSummary.photoCount) Fotos",
                    color: .orange
                )
            }
        }
    }

    private func infoChip(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - Section Card

    private func sectionCard(_ section: ReportSection, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section number + heading
            HStack(alignment: .top, spacing: 12) {
                Text("\(index + 1)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.teal, in: Circle())

                Text(section.heading)
                    .font(.subheadline.weight(.semibold))
            }

            // Body text
            Text(section.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Photos grid
            if !section.photoIndices.isEmpty {
                let validPhotos = section.photoIndices.filter { $0 < controller.photos.count }
                if !validPhotos.isEmpty {
                    Divider()
                    photoGrid(validPhotos)
                }
            }

            // Measurements
            if !section.measurementIndices.isEmpty {
                let measurements = controller.evaluation.services.flatMap(\.associatedMeasurements)
                let validMeasurements = section.measurementIndices.filter { $0 < measurements.count }
                if !validMeasurements.isEmpty {
                    Divider()
                    HStack(spacing: 8) {
                        Image(systemName: "ruler")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.teal)
                        ForEach(validMeasurements.prefix(4), id: \.self) { idx in
                            let m = measurements[idx]
                            HStack(spacing: 4) {
                                Image(systemName: m.type == .area ? "square.dashed" : "arrow.left.and.right")
                                    .font(.system(size: 10))
                                Text(m.formattedValue)
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(.teal)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.teal.opacity(0.08))
                            .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func photoGrid(_ indices: [Int]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: min(indices.count, 3))
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(indices.prefix(6), id: \.self) { idx in
                Image(uiImage: controller.photos[idx].image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if indices.count > 6 {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.tertiarySystemBackground))
                    Text("+\(indices.count - 6)")
                        .font(.headline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 80, maxHeight: 100)
            }
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Sticky Action Bar

    private var stickyActionBar: some View {
        VStack(spacing: 10) {
            if controller.isCompleted {
                Button(action: onDone) {
                    Label("Fertig", systemImage: "checkmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(Color.green, in: RoundedRectangle(cornerRadius: 14))
                }
            } else {
                Button {
                    Task { await controller.createReport() }
                } label: {
                    if controller.isCreating {
                        VStack(spacing: 6) {
                            ProgressView()
                            Text(controller.isUploading
                                 ? "Fotos hochladen (\(Int(controller.uploadProgress * 100))%)"
                                 : "Bericht wird gespeichert…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    } else {
                        Label("\(controller.reportTitle) speichern", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(.white)
                            .background(Color.teal, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .disabled(controller.isWorking || controller.generatedReport == nil)

                Button {
                    Task { await controller.generateReport() }
                } label: {
                    Label("Neu generieren", systemImage: "arrow.counterclockwise")
                        .font(.subheadline)
                        .foregroundStyle(.teal)
                }
                .disabled(controller.isWorking)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}
