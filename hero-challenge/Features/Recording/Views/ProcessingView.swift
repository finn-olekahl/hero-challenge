import SwiftUI

/// Animated processing screen shown while the AI evaluates the recording.
/// Shows a session recap and animated progress phases to make the wait feel shorter.
struct ProcessingView: View {
    var controller: RecordingController
    var onComplete: (AIEvaluation) -> Void
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            PhasedProgressView(
                title: "KI-Auswertung läuft",
                subtitle: "Deine Aufnahme wird analysiert",
                icon: "brain",
                accentColor: .blue,
                phases: [
                    .init(icon: "waveform", label: "Transkript wird verarbeitet"),
                    .init(icon: "wrench.and.screwdriver", label: "Leistungen werden erkannt"),
                    .init(icon: "shippingbox", label: "Materialien werden zugeordnet"),
                    .init(icon: "questionmark.bubble", label: "Offene Fragen werden formuliert"),
                ],
                recapStats: [
                    .init(icon: "clock", value: controller.formattedElapsedTime, label: "Dauer"),
                    .init(icon: "photo", value: "\(controller.photoCount)", label: controller.photoCount == 1 ? "Foto" : "Fotos"),
                    .init(icon: "ruler", value: "\(controller.measurementCount)", label: controller.measurementCount == 1 ? "Messung" : "Messungen"),
                ],
                isComplete: controller.state == .completed && controller.evaluation != nil,
                onAllPhasesComplete: {
                    if let evaluation = controller.evaluation {
                        onComplete(evaluation)
                    }
                }
            )

            // Top-left cancel button
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
        }
        .alert("Fehler", isPresented: .init(
            get: { controller.hasError },
            set: { if !$0 { controller.clearError() } }
        )) {
            Button("Nochmal versuchen") {
                controller.clearError()
                Task { await controller.retryEvaluation() }
            }
            Button("Abbrechen", role: .cancel) {
                controller.clearError()
                onCancel()
            }
        } message: {
            Text(controller.errorMessage ?? "Ein Fehler ist aufgetreten")
        }
    }
}
