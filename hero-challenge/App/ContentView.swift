import SwiftUI

/// Main content view that manages the full AI-Modus flow:
/// Start → Recording → Questionnaire → Offer Creation
struct ContentView: View {
    @State private var appState: AppFlowState = .home
    @State private var recordingController = RecordingController()
    @State private var evaluation: AIEvaluation?
    @State private var questionnaireController: QuestionnaireController?
    @State private var offerController: OfferController?
    @State private var reportController: ReportController?

    // API service (configured once)
    private let apiService: HeroAPIService = {
        let client = GraphQLClient(
            baseURL: URL(string: EnvConfig.heroAPIURL)!,
            token: EnvConfig.heroAPIToken
        )
        return HeroAPIService(client: client)
    }()

    var body: some View {
        Group {
            switch appState {
            case .home:
                homeView

            case .recording:
                RecordingView(
                    controller: recordingController,
                    onStopRecording: {
                        withAnimation {
                            appState = .processing
                        }
                    },
                    onCancel: {
                        recordingController.reset()
                        withAnimation {
                            appState = .home
                        }
                    }
                )

            case .processing:
                ProcessingView(
                    controller: recordingController,
                    apiService: apiService,
                    onComplete: { qc in
                        self.evaluation = qc.evaluation
                        self.questionnaireController = qc
                        withAnimation {
                            appState = .questionnaire
                        }
                    },
                    onNeedsClarification: {
                        withAnimation {
                            appState = .clarification
                        }
                    },
                    onCancel: {
                        recordingController.reset()
                        withAnimation {
                            appState = .home
                        }
                    }
                )

            case .clarification:
                ClarificationView(
                    controller: recordingController,
                    onComplete: {
                        // After clarification, show evaluating spinner then questionnaire
                        withAnimation {
                            appState = .evaluating
                        }
                    },
                    onCancel: {
                        recordingController.reset()
                        withAnimation {
                            appState = .home
                        }
                    }
                )

            case .evaluating:
                ProcessingView(
                    controller: recordingController,
                    apiService: apiService,
                    onComplete: { qc in
                        self.evaluation = qc.evaluation
                        self.questionnaireController = qc
                        withAnimation {
                            appState = .questionnaire
                        }
                    },
                    onNeedsClarification: {
                        // Should not happen in evaluating phase, but handle gracefully
                        withAnimation {
                            appState = .clarification
                        }
                    },
                    onCancel: {
                        recordingController.reset()
                        withAnimation {
                            appState = .home
                        }
                    }
                )

            case .questionnaire:
                if let qc = questionnaireController {
                    QuestionnaireView(
                        controller: qc,
                        onComplete: { answers in
                            if let eval = evaluation {
                                let intent = eval.intent
                                switch intent {
                                case .offer:
                                    let oc = OfferController(
                                        evaluation: eval,
                                        answers: answers,
                                        apiService: apiService,
                                        transcript: self.recordingController.currentTranscript
                                    )
                                    self.offerController = oc
                                    withAnimation {
                                        appState = .offer
                                    }
                                case .workReport, .siteReport:
                                    let rc = ReportController(
                                        intent: intent,
                                        evaluation: eval,
                                        answers: answers,
                                        photos: self.recordingController.capturedPhotos,
                                        apiService: apiService,
                                        transcript: self.recordingController.currentTranscript
                                    )
                                    self.reportController = rc
                                    withAnimation {
                                        appState = .report
                                    }
                                }
                            }
                        },
                        onCancel: {
                            withAnimation {
                                appState = .home
                            }
                        }
                    )
                }

            case .report:
                if let rc = reportController {
                    ReportView(
                        controller: rc,
                        onDone: {
                            resetAll()
                            withAnimation {
                                appState = .home
                            }
                        }
                    )
                }

            case .offer:
                if let oc = offerController {
                    OfferView(
                        controller: oc,
                        onDone: {
                            resetAll()
                            withAnimation {
                                appState = .home
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Home View

    private var homeView: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Hero branding
                VStack(spacing: 12) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 56))
                        .foregroundStyle(.blue)

                    Text("AI-Modus")
                        .font(.largeTitle.weight(.bold))

                    Text("Sprechen, fotografieren, messen –\ndie KI erstellt Angebot oder Bericht.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Feature cards
                VStack(spacing: 12) {
                    featureCard(icon: "mic.fill", title: "Sprachaufnahme", description: "Automatische Transkription mit Zeitstempeln")
                    featureCard(icon: "camera.fill", title: "Fotodokumentation", description: "Fotos werden dem Gesprächskontext zugeordnet")
                    featureCard(icon: "ruler.fill", title: "AR-Messung", description: "Längen und Flächen direkt per Kamera messen")
                }
                .padding(.horizontal)

                Spacer()

                // Start button
                Button {
                    recordingController = RecordingController()
                    withAnimation {
                        appState = .recording
                    }
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Aufnahme starten")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundStyle(.white)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationTitle("HERO")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func featureCard(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func resetAll() {
        recordingController.reset()
        evaluation = nil
        questionnaireController = nil
        offerController = nil
        reportController = nil
    }
}

enum AppFlowState {
    case home
    case recording
    case processing
    case clarification
    case evaluating
    case questionnaire
    case offer
    case report
}
