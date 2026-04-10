import Foundation

/// Service that uses OpenAI to generate structured report content
/// (Arbeitsbericht or Baustellenbericht) from the AI evaluation + timeline.
final class ReportGenerationService: Sendable {
    private let openAIClient: OpenAIClient?
    private let model: String

    init() {
        if EnvConfig.isConfigured {
            self.openAIClient = OpenAIClient(apiKey: EnvConfig.openAIAPIKey)
            self.model = EnvConfig.mainModel
        } else {
            self.openAIClient = nil
            self.model = ""
        }
    }

    func generateReport(
        intent: DocumentIntent,
        evaluation: AIEvaluation,
        answers: QuestionnaireController.CollectedAnswers,
        transcript: String,
        photoCount: Int,
        measurements: [ARMeasurement]
    ) async throws -> GeneratedReport {
        if let client = openAIClient {
            return try await generateWithOpenAI(
                client: client,
                intent: intent,
                evaluation: evaluation,
                answers: answers,
                transcript: transcript,
                photoCount: photoCount,
                measurements: measurements
            )
        }
        return buildFallbackReport(
            intent: intent,
            evaluation: evaluation,
            transcript: transcript,
            photoCount: photoCount,
            measurements: measurements
        )
    }

    // MARK: - OpenAI Generation

    private func generateWithOpenAI(
        client: OpenAIClient,
        intent: DocumentIntent,
        evaluation: AIEvaluation,
        answers: QuestionnaireController.CollectedAnswers,
        transcript: String,
        photoCount: Int,
        measurements: [ARMeasurement]
    ) async throws -> GeneratedReport {
        let systemPrompt = buildSystemPrompt(intent: intent)
        let userPrompt = buildUserPrompt(
            intent: intent,
            evaluation: evaluation,
            answers: answers,
            transcript: transcript,
            photoCount: photoCount,
            measurements: measurements
        )

        let response: OpenAIReportResponse = try await client.chatCompletion(
            model: model,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            responseType: OpenAIReportResponse.self
        )

        return response.toGeneratedReport()
    }

    private func buildSystemPrompt(intent: DocumentIntent) -> String {
        let reportType: String
        let reportDescription: String

        switch intent {
        case .workReport:
            reportType = "Arbeitsbericht"
            reportDescription = """
            Ein Arbeitsbericht dokumentiert abgeschlossene Arbeiten.
            Schreibe in Vergangenheitsform. Professionell und sachlich.
            """
        case .siteReport:
            reportType = "Baustellenbericht"
            reportDescription = """
            Ein Baustellenbericht dokumentiert den aktuellen Fortschritt auf einer Baustelle.
            Schreibe sachlich und dokumentarisch.
            """
        case .offer:
            reportType = "Bericht"
            reportDescription = "Ein allgemeiner Bericht."
        }

        return """
        Du bist ein KI-Assistent für die HERO Handwerker-Software. \
        Deine Aufgabe ist es, aus einer Aufnahme eines Handwerkers vor Ort \
        einen professionellen \(reportType) zu erstellen.

        \(reportDescription)

        Der Bericht wird als Richtext mit eingebetteten Fotos im HERO-System gespeichert.

        **Foto-Referenzen:** Du erhältst die Anzahl der aufgenommenen Fotos (0-basierte Indizes). \
        Ordne Fotos den passenden Abschnitten zu über `photo_indices`. \
        ALLE Fotos müssen in mindestens einem Abschnitt referenziert werden.

        **Messungen:** Du erhältst eine Liste der durchgeführten Messungen (0-basierte Indizes). \
        Referenziere Messungen im Text und über `measurement_indices`. \
        ALLE Messungen müssen in mindestens einem Abschnitt referenziert werden.

        Antworte als JSON:
        {
          "title": "Berichtstitel",
          "summary": "Kurze Zusammenfassung (1-2 Sätze)",
          "sections": [
            {
              "heading": "Abschnittsüberschrift",
              "body": "Ausführlicher Fließtext des Abschnitts. Kann mehrere Absätze enthalten.",
              "photo_indices": [0, 1],
              "measurement_indices": [0]
            }
          ]
        }

        Regeln:
        - **WICHTIGSTE REGEL: Schreibe NUR über Dinge, die im Transkript tatsächlich gesagt wurden.** \
        Erfinde KEINE Details, Materialmengen, Arbeitsschritte oder Beobachtungen, \
        die nicht explizit im Transkript vorkommen. Wenn etwas unklar ist, lass es weg.
        - Erstelle 2-5 sinnvolle Abschnitte je nach Umfang
        - Jeder Abschnitt hat eine klare Überschrift
        - Der body enthält professionellen Fließtext
        - ALLE Fotos müssen über photo_indices zugeordnet werden (Indizes 0 bis N-1)
        - ALLE Messungen müssen über measurement_indices zugeordnet werden
        - Alle Texte auf Deutsch, professionelle Handwerker-Sprache
        """
    }

    private func buildUserPrompt(
        intent: DocumentIntent,
        evaluation: AIEvaluation,
        answers: QuestionnaireController.CollectedAnswers,
        transcript: String,
        photoCount: Int,
        measurements: [ARMeasurement]
    ) -> String {
        var prompt = "## Original-Transkript (einzige Quelle für Inhalte)\n\(transcript)\n\n"

        prompt += "## Erkannte Leistungen (nur als Orientierung – keine Details hinzufügen die nicht im Transkript stehen)\n"
        for service in evaluation.services {
            prompt += "- \(service.name): \(service.description)\n"
        }

        if !evaluation.materials.isEmpty {
            prompt += "\n## Erkannte Materialkategorien (nur erwähnen wenn im Transkript genannt)\n"
            for material in evaluation.materials {
                prompt += "- \(material.category)\n"
            }
        }

        prompt += "\n## Fotos\n\(photoCount) Foto(s) aufgenommen (Indizes 0 bis \(max(0, photoCount - 1)))\n"

        if !measurements.isEmpty {
            prompt += "\n## Messungen\n"
            for (i, m) in measurements.enumerated() {
                let typeDesc = m.type == .area ? "Flächenmessung" : "Längenmessung"
                prompt += "[\(i)] \(typeDesc): \(m.formattedValue)\n"
            }
        }

        if let project = answers.project {
            prompt += "\n## Projekt\n\(project.displayName)\n"
        }

        if !answers.freeTextAnswers.isEmpty {
            prompt += "\n## Weitere Angaben\n"
            for answer in answers.freeTextAnswers {
                if !answer.answer.isEmpty {
                    prompt += "- \(answer.question): \(answer.answer)\n"
                }
            }
        }

        return prompt
    }

    // MARK: - Fallback

    private func buildFallbackReport(
        intent: DocumentIntent,
        evaluation: AIEvaluation,
        transcript: String,
        photoCount: Int,
        measurements: [ARMeasurement]
    ) -> GeneratedReport {
        let title: String
        switch intent {
        case .workReport:
            title = evaluation.context?.suggestedProjectName.map { "Arbeitsbericht – \($0)" }
                ?? "Arbeitsbericht"
        case .siteReport:
            title = evaluation.context?.suggestedProjectName.map { "Baustellenbericht – \($0)" }
                ?? "Baustellenbericht"
        case .offer:
            title = "Bericht"
        }

        var sections: [ReportSection] = []

        // Overview section
        let servicesText = evaluation.services.map { "- \($0.name): \($0.description)" }.joined(separator: "\n")
        sections.append(ReportSection(
            heading: "Durchgeführte Arbeiten",
            body: servicesText.isEmpty ? "Keine Leistungen erkannt." : servicesText
        ))

        // Measurements section
        if !measurements.isEmpty {
            let mText = measurements.enumerated().map { (i, m) in
                "\(m.type == .area ? "Fläche" : "Länge"): \(m.formattedValue)"
            }.joined(separator: "\n")
            sections.append(ReportSection(
                heading: "Messungen",
                body: mText,
                measurementIndices: Array(0..<measurements.count)
            ))
        }

        // Photos section
        if photoCount > 0 {
            sections.append(ReportSection(
                heading: "Fotodokumentation",
                body: "\(photoCount) Foto(s) aufgenommen.",
                photoIndices: Array(0..<photoCount)
            ))
        }

        return GeneratedReport(
            title: title,
            summary: "Automatisch generierter Bericht aus Vor-Ort-Aufnahme.",
            sections: sections
        )
    }
}

// MARK: - OpenAI Response

private struct OpenAIReportResponse: Decodable {
    let title: String
    let summary: String
    let sections: [SectionResponse]

    struct SectionResponse: Decodable {
        let heading: String
        let body: String
        let photo_indices: [Int]?
        let measurement_indices: [Int]?
    }

    func toGeneratedReport() -> GeneratedReport {
        GeneratedReport(
            title: title,
            summary: summary,
            sections: sections.map {
                ReportSection(
                    heading: $0.heading,
                    body: $0.body,
                    photoIndices: $0.photo_indices ?? [],
                    measurementIndices: $0.measurement_indices ?? []
                )
            }
        )
    }
}
