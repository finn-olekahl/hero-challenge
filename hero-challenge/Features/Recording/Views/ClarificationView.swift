import SwiftUI

/// Shown when the AI pre-scan found genuinely unclear points in the recording.
/// This should appear rarely — only when the transcript is truly ambiguous.
struct ClarificationView: View {
    var controller: RecordingController
    var onComplete: () -> Void
    var onCancel: () -> Void

    @State private var answers: [UUID: String] = [:]
    @State private var isSubmitting = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

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

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 8) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 40, weight: .medium))
                                .foregroundStyle(.orange)

                            Text("Kurze Rückfrage")
                                .font(.title2.weight(.bold))

                            Text("Einige Punkte aus deiner Aufnahme waren nicht ganz klar.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 16)

                        ForEach(controller.pendingQuestions) { question in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(question.question)
                                    .font(.subheadline.weight(.medium))

                                if let context = question.context, !context.isEmpty {
                                    Text(context)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                TextField("Antwort", text: binding(for: question.id), axis: .vertical)
                                    .textFieldStyle(.roundedBorder)
                                    .lineLimit(2...5)
                            }
                            .padding(16)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }


                VStack(spacing: 10) {
                    Button {
                        submit()
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        } else {
                            Text("Weiter")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSubmitting)

                    Button("Überspringen") {
                        skip()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .disabled(isSubmitting)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
    }

    private func binding(for id: UUID) -> Binding<String> {
        Binding(
            get: { answers[id, default: ""] },
            set: { answers[id] = $0 }
        )
    }

    private func submit() {
        isSubmitting = true
        let clarifications = controller.pendingQuestions.compactMap { q -> (String, String)? in
            let answer = answers[q.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else { return nil }
            return (q.question, answer)
        }

        Task {
            if clarifications.isEmpty {
                await controller.skipClarifications()
            } else {
                await controller.submitClarifications(clarifications)
            }
            onComplete()
        }
    }

    private func skip() {
        isSubmitting = true
        Task {
            await controller.skipClarifications()
            onComplete()
        }
    }
}
