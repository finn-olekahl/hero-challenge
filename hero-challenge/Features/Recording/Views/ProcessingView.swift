import SwiftUI

/// Animated processing screen shown while the AI evaluates the recording.
/// Shows a session recap and animated progress phases to make the wait feel shorter.
struct ProcessingView: View {
    var controller: RecordingController
    var apiService: HeroAPIService
    var onComplete: (QuestionnaireController) -> Void
    var onNeedsClarification: (() -> Void)?
    var onCancel: () -> Void

    @State private var visiblePhases: Int = 0
    @State private var completedPhases: Int = 0
    @State private var showRecap: Bool = false
    @State private var pulseAnimation: Bool = false

    private let phases = [
        ProcessingPhase(icon: "waveform", label: "Transkript wird verarbeitet"),
        ProcessingPhase(icon: "wrench.and.screwdriver", label: "Leistungen werden erkannt"),
        ProcessingPhase(icon: "folder", label: "Projekt wird zugeordnet"),
        ProcessingPhase(icon: "shippingbox", label: "Produkte werden abgeglichen")
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemBackground), Color.blue.opacity(0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .background(Color(.tertiarySystemFill), in: Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer().frame(height: 24)

                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(Color.blue.opacity(0.15 - Double(i) * 0.04), lineWidth: 1.5)
                            .frame(width: CGFloat(80 + i * 28), height: CGFloat(80 + i * 28))
                            .scaleEffect(pulseAnimation ? 1.08 : 0.95)
                            .animation(
                                .easeInOut(duration: 1.8)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.3),
                                value: pulseAnimation
                            )
                    }

                    Image(systemName: "brain")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.blue)
                        .frame(width: 72, height: 72)
                        .background(Color.blue.opacity(0.1), in: Circle())
                }
                .padding(.bottom, 28)

                // Title
                Text("KI-Auswertung läuft")
                    .font(.title2.weight(.bold))
                    .padding(.bottom, 6)

                Text("Deine Aufnahme wird analysiert")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 32)

                // Session recap card
                if showRecap {
                    recapCard
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
                            phaseRow(phase: phase, index: index)
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
        .onChange(of: controller.state) { _, newState in
            if newState == .completed, let evaluation = controller.evaluation {
                Task {
                    let qc = QuestionnaireController(evaluation: evaluation, apiService: apiService, transcript: controller.currentTranscript)
                    await qc.loadDropdownData()  // this will fetch + autoMatch
                    
                    await MainActor.run {
                        completeAllPhasesAndFinish(qc: qc)
                    }
                }
            } else if newState == .clarification {
                // Pre-scan found questions — navigate to clarification
                completeAllPhasesAndNavigate {
                    onNeedsClarification?()
                }
            }
        }
        .alert("Fehler", isPresented: .init(
            get: { controller.hasError },
            set: { if !$0 { controller.clearError() } }
        )) {
            Button("Nochmal versuchen") {
                controller.clearError()
                Task { await controller.retryEvaluation() }
                // Reset phase animations
                completedPhases = 0
                visiblePhases = 0
                startPhaseAnimations()
            }
            Button("Abbrechen", role: .cancel) {
                controller.clearError()
                onCancel()
            }
        } message: {
            Text(controller.errorMessage ?? "Ein Fehler ist aufgetreten")
        }
    }

    // MARK: - Recap Card

    private var recapCard: some View {
        HStack(spacing: 16) {
            recapStat(
                icon: "clock",
                value: controller.formattedElapsedTime,
                label: "Dauer"
            )

            divider

            recapStat(
                icon: "photo",
                value: "\(controller.photoCount)",
                label: controller.photoCount == 1 ? "Foto" : "Fotos"
            )

            divider

            recapStat(
                icon: "ruler",
                value: "\(controller.measurementCount)",
                label: controller.measurementCount == 1 ? "Messung" : "Messungen"
            )
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
                .foregroundStyle(.blue)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: 1, height: 36)
    }

    // MARK: - Phase Row

    private func phaseRow(phase: ProcessingPhase, index: Int) -> some View {
        HStack(spacing: 14) {
            ZStack {
                if index < completedPhases {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                } else if index == completedPhases {
                    // Active phase - spinning
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.blue)
                } else {
                    Image(systemName: phase.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                        .frame(width: 22, height: 22)
                }
            }
            .frame(width: 26, height: 26)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: completedPhases)

            Text(phase.label)
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

    // MARK: - Phase Animation Logic

    private func startPhaseAnimations() {
        // Show recap card after a short delay
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
            withAnimation { completedPhases = max(completedPhases, 1) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            withAnimation { completedPhases = max(completedPhases, 2) }
        }
    }

    private func completeAllPhasesAndFinish(qc: QuestionnaireController) {
        completeAllPhasesAndNavigate {
            onComplete(qc)
        }
    }

    private func completeAllPhasesAndNavigate(action: @escaping () -> Void) {
        let remaining = phases.count - completedPhases
        for i in 0..<remaining {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.3) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    completedPhases = min(completedPhases + 1, phases.count)
                }
            }
        }

        let navigationDelay = Double(remaining) * 0.3 + 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + navigationDelay) {
            action()
        }
    }
}

// MARK: - Supporting Types

private struct ProcessingPhase {
    let icon: String
    let label: String
}
