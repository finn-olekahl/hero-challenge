import SwiftUI

/// Animated processing screen shown while the AI evaluates the recording.
/// Shows a session recap and animated progress phases to make the wait feel shorter.
struct ProcessingView: View {
    var controller: RecordingController
    var onComplete: (AIEvaluation) -> Void
    var onCancel: () -> Void

    @State private var completedPhases: Int = 0

    private let phases = [
        ProgressPhase(icon: "waveform", label: "Transkript wird verarbeitet"),
        ProgressPhase(icon: "wrench.and.screwdriver", label: "Leistungen werden erkannt"),
        ProgressPhase(icon: "shippingbox", label: "Materialien werden zugeordnet"),
        ProgressPhase(icon: "questionmark.bubble", label: "Offene Fragen werden formuliert"),
    ]

    var body: some View {
        ZStack {
            // Top bar with cancel
            VStack {
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
                Spacer()
            }

            PhasedProgressView(
                accentColor: .blue,
                icon: "brain",
                title: "KI-Auswertung läuft",
                subtitle: "Deine Aufnahme wird analysiert",
                phases: phases,
                completedPhases: completedPhases
            ) {
                RecapCard(stats: [
                    RecapStat(icon: "clock", value: controller.formattedElapsedTime, label: "Dauer"),
                    RecapStat(icon: "photo", value: "\(controller.photoCount)", label: controller.photoCount == 1 ? "Foto" : "Fotos"),
                    RecapStat(icon: "ruler", value: "\(controller.measurementCount)", label: controller.measurementCount == 1 ? "Messung" : "Messungen"),
                ], accentColor: .blue)
            }
        }
        .onAppear {
            startTimedPhaseCompletion()
        }
        .onChange(of: controller.state) { _, newState in
            if newState == .completed, let evaluation = controller.evaluation {
                completeAllPhasesAndFinish(evaluation: evaluation)
            }
        }
        .alert("Fehler", isPresented: .init(
            get: { controller.hasError },
            set: { if !$0 { controller.clearError() } }
        )) {
            Button("Nochmal versuchen") {
                controller.clearError()
                Task { await controller.retryEvaluation() }
                completedPhases = 0
                startTimedPhaseCompletion()
            }
            Button("Abbrechen", role: .cancel) {
                controller.clearError()
                onCancel()
            }
        } message: {
            Text(controller.errorMessage ?? "Ein Fehler ist aufgetreten")
        }
    }

    // MARK: - Phase Animation Logic

    private func startTimedPhaseCompletion() {
        // Phase 0 ("Transkript") completes quickly — it's already done
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { completedPhases = 1 }
        }
        // Phase 1 ("Leistungen") takes a bit longer
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            withAnimation { completedPhases = max(completedPhases, 2) }
        }
        // Phases 2 and 3 only complete when the AI actually finishes (handled in onChange)
    }

    private func completeAllPhasesAndFinish(evaluation: AIEvaluation) {
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
            onComplete(evaluation)
        }
    }
}
