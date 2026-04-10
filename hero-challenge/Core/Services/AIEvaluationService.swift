import Foundation

/// Service that processes the recording timeline and produces a structured AI evaluation.
/// Uses OpenAI Chat Completions when configured, falls back to keyword-based mock otherwise.
final class AIEvaluationService: Sendable {
    private let openAIClient: OpenAIClient?
    private let model: String

    init(openAIClient: OpenAIClient? = EnvConfig.openAIClient, model: String = EnvConfig.mainModel) {
        self.openAIClient = openAIClient
        self.model = model
    }

    func evaluate(timeline: RecordingTimeline, photos: [CapturedPhoto]) async throws -> AIEvaluation {
        let transcriptParts = timeline.entries.compactMap { $0.content.transcriptText }
        let fullTranscript = transcriptParts.joined(separator: " ")
        let measurements = timeline.entries.compactMap { $0.content.measurementValue }

        if let client = openAIClient {
            return try await evaluateWithOpenAI(
                client: client,
                transcript: fullTranscript,
                measurements: measurements,
                photoCount: photos.count
            )
        }

        return buildMockEvaluation(
            transcript: fullTranscript,
            measurements: measurements
        )
    }

    // MARK: - OpenAI Evaluation

    private func evaluateWithOpenAI(
        client: OpenAIClient,
        transcript: String,
        measurements: [ARMeasurement],
        photoCount: Int
    ) async throws -> AIEvaluation {
        let systemPrompt = buildSystemPrompt()
        let userPrompt = buildUserPrompt(
            transcript: transcript,
            measurements: measurements,
            photoCount: photoCount
        )

        let response: OpenAIEvaluationResponse = try await client.chatCompletion(
            model: model,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            responseType: OpenAIEvaluationResponse.self
        )

        return response.toAIEvaluation(measurements: measurements)
    }

    private func buildSystemPrompt() -> String {
        """
        Du bist ein KI-Assistent für die HERO Handwerker-Software. \
        Deine Aufgabe ist es, aus einer Aufnahme (Transkript + Messungen + Fotos) \
        eines Handwerkers vor Ort ein strukturiertes Angebot vorzubereiten.

        Analysiere das Transkript und die Messungen und identifiziere:
        1. **Leistungen** (services): Welche Arbeiten sollen durchgeführt werden?
        2. **Materialien** (materials): Welche Materialien / Artikelkategorien werden benötigt? \
           Gib keine konkreten Produkte an, sondern Kategorien (z.B. "Fliesen", "Wandfarbe").
        3. **Auftragskontext** (context): Kundenname, Projektname, Ort.
           - **suggested_project_name**: Schlage IMMER einen Projektnamen vor, auch wenn keiner explizit genannt wurde. \
             Leite den Namen aus den erkannten Leistungen, dem Ort oder dem Kundenkontext ab \
             (z.B. "Badsanierung Müller", "Fliesenarbeiten Küche", "Malerarbeiten EG"). \
             Nur null wenn das Transkript komplett leer oder unverständlich ist.
        4. **Offene Fragen** (open_questions): Was fehlt noch, um ein vollständiges Angebot zu erstellen?

        Verknüpfe Messungen mit den passenden Leistungen und Materialien. \
        Berechne vorgeschlagene Mengen aus den Messungen (z.B. Fläche + 10% Verschnitt für Fliesen).

        Antworte ausschließlich als JSON-Objekt mit folgendem Schema:
        {
          "services": [
            {
              "name": "string",
              "description": "string",
              "measurement_indices": [0],
              "suggested_quantity": 12.5,
              "suggested_unit": "m²"
            }
          ],
          "materials": [
            {
              "category": "string",
              "description": "string",
              "suggested_quantity": 15.0,
              "suggested_unit": "m²",
              "derived_from_measurement_index": 0
            }
          ],
          "context": {
            "suggested_project_name": "string – IMMER ausfüllen, aus Leistungen/Ort/Kunde ableiten",
            "customer_name": "string oder null",
            "location": "string oder null"
          },
          "open_questions": [
            {
              "question": "string",
              "context": "string"
            }
          ]
        }

        Regeln:
        - measurement_indices bezieht sich auf den Index in der Messungsliste (0-basiert).
        - derived_from_measurement_index: Index der Messung, aus der die Menge abgeleitet wurde, oder null.
        - Wenn keine spezifischen Leistungen erkannt werden, erstelle eine generische "Handwerkerleistung".
        - suggested_project_name MUSS immer gesetzt sein. Erstelle einen kurzen, beschreibenden Namen \
          aus den Leistungen und ggf. Kundenname/Ort (z.B. "Badsanierung", "Elektroarbeiten Neubau", "Fliesenarbeiten Schmidt").
        - Stelle MAXIMAL 2 offene Fragen. Nur fragen, was WIRKLICH fehlt und nicht aus dem Transkript ableitbar ist. \
          Frage NICHT nach Zeitraum (wird separat abgefragt). \
          Frage NICHT nach konkreten Produkten (werden separat ausgewählt). \
          Frage NICHT nach Mengen (werden aus Messungen abgeleitet). \
          Gute Fragen: Materialqualität, Untergrundvorbereitung, Entsorgung, Zugang.
        - **Einheiten für Leistungen** (services): Verwende die Einheit, in der die Arbeit abgerechnet wird. \
          Erlaubte Werte: m², Std, lfm, Stk, pauschal, kg, L, m. \
          NIEMALS "psch" verwenden – der korrekte Wert ist "pauschal". \
          Z.B. Malerarbeiten → m², Elektroinstallation → Std.
        - **Einheiten für Materialien** (materials): Verwende die Einkaufs-/Verbrauchseinheit des Materials, \
          NICHT die Flächeneinheit der Leistung. \
          Erlaubte Werte: m², Std, lfm, Stk, pauschal, kg, L, m. \
          Beispiele: Wandfarbe → L, Fliesenkleber → kg, Fliesen → m², Schrauben → Stk, \
          Silikon → Stk (Kartuschen), Kabel → m, Tapete → Stk. \
          NIEMALS "l" (klein) verwenden – der korrekte Wert ist "L" (groß). \
          Berechne die Materialmenge in der korrekten Einkaufseinheit aus den Messungen \
          (z.B. 20m² Wand × 0.15 L/m² = 3.0 L Farbe; 12m² × 3.5 kg/m² = 42 kg Kleber).
        - Alle Texte auf Deutsch.
        """
    }

    private func buildUserPrompt(transcript: String, measurements: [ARMeasurement], photoCount: Int) -> String {
        var prompt = "## Transkript der Aufnahme\n\(transcript)\n\n"

        if !measurements.isEmpty {
            prompt += "## Messungen\n"
            for (i, m) in measurements.enumerated() {
                let typeDesc = m.type == .area ? "Flächenmessung" : "Längenmessung"
                prompt += "[\(i)] \(typeDesc): \(m.formattedValue)\n"
            }
            prompt += "\n"
        }

        prompt += "## Fotos\n\(photoCount) Foto(s) aufgenommen.\n"

        return prompt
    }

    // MARK: - Mock Fallback

    private func buildMockEvaluation(transcript: String, measurements: [ARMeasurement]) -> AIEvaluation {
        var services: [IdentifiedService] = []
        var materials: [IdentifiedMaterial] = []
        var questions: [OpenQuestion] = []

        let lower = transcript.lowercased()

        if lower.contains("fliese") || lower.contains("boden") {
            let areaM = measurements.filter { $0.type == .area }
            let area = areaM.first?.value
            services.append(IdentifiedService(
                name: "Fliesenverlegung",
                description: "Boden- oder Wandfliesen verlegen",
                associatedMeasurements: areaM,
                suggestedQuantity: area,
                suggestedUnit: "m²"
            ))
            materials.append(IdentifiedMaterial(
                category: "Fliesen",
                description: "Bodenfliesen passend zum Raum",
                suggestedQuantity: area.map { $0 * 1.1 },
                suggestedUnit: "m²",
                derivedFromMeasurement: areaM.first
            ))
            materials.append(IdentifiedMaterial(
                category: "Fliesenkleber",
                description: "Flexkleber für Bodenfliesen",
                suggestedQuantity: area.map { $0 * 3.5 },
                suggestedUnit: "kg"
            ))
        }

        if lower.contains("wand") || lower.contains("streich") || lower.contains("maler") {
            let areaM = measurements.filter { $0.type == .area }
            services.append(IdentifiedService(
                name: "Malerarbeiten",
                description: "Wände streichen / tapezieren",
                associatedMeasurements: areaM,
                suggestedQuantity: areaM.first?.value,
                suggestedUnit: "m²"
            ))
            materials.append(IdentifiedMaterial(
                category: "Wandfarbe",
                description: "Innenfarbe weiß",
                suggestedQuantity: areaM.first.map { $0.value * 0.15 },
                suggestedUnit: "l"
            ))
        }

        if lower.contains("rohr") || lower.contains("sanitär") || lower.contains("wasser") {
            let lengthM = measurements.filter { $0.type == .length }
            services.append(IdentifiedService(
                name: "Sanitärinstallation",
                description: "Rohrverlegung und Anschlussarbeiten",
                associatedMeasurements: lengthM,
                suggestedQuantity: lengthM.first?.value,
                suggestedUnit: "m"
            ))
        }

        if lower.contains("elektr") || lower.contains("steckdose") || lower.contains("licht") {
            services.append(IdentifiedService(
                name: "Elektroinstallation",
                description: "Elektroarbeiten",
                suggestedQuantity: nil,
                suggestedUnit: "Std."
            ))
        }

        if services.isEmpty {
            services.append(IdentifiedService(
                name: "Handwerkerleistung",
                description: "Aus dem Gespräch identifizierte Leistung",
                associatedMeasurements: measurements,
                suggestedQuantity: nil,
                suggestedUnit: nil
            ))
        }

        questions.append(OpenQuestion(
            question: "Gibt es besondere Anforderungen an die Materialqualität?",
            context: "Keine Angaben im Gespräch gefunden"
        ))

        if measurements.isEmpty {
            questions.append(OpenQuestion(
                question: "Welche Flächen bzw. Maße sind betroffen?",
                context: "Keine Messungen während der Aufnahme durchgeführt"
            ))
        }

        let context = extractOrderContext(from: transcript)

        return AIEvaluation(
            services: services,
            materials: materials,
            context: context,
            openQuestions: questions
        )
    }

    private func extractOrderContext(from transcript: String) -> OrderContext {
        var projectName: String?
        var customerName: String?
        let words = transcript.components(separatedBy: .whitespaces)

        for (i, word) in words.enumerated() {
            let lower = word.lowercased()
            if (lower == "herr" || lower == "frau") && i + 1 < words.count {
                customerName = "\(word) \(words[i + 1])"
            }
            if lower == "projekt" && i + 1 < words.count {
                projectName = words[i + 1]
            }
        }

        return OrderContext(
            suggestedProjectName: projectName,
            suggestedProjectId: nil,
            customerName: customerName,
            location: nil
        )
    }
}

// MARK: - OpenAI Response Mapping

/// Decodable shape matching the JSON schema we ask OpenAI to return.
private struct OpenAIEvaluationResponse: Decodable {
    let services: [ServiceResponse]
    let materials: [MaterialResponse]
    let context: ContextResponse?
    let open_questions: [QuestionResponse]

    struct ServiceResponse: Decodable {
        let name: String
        let description: String
        let measurement_indices: [Int]?
        let suggested_quantity: Double?
        let suggested_unit: String?
    }

    struct MaterialResponse: Decodable {
        let category: String
        let description: String
        let suggested_quantity: Double?
        let suggested_unit: String?
        let derived_from_measurement_index: Int?
    }

    struct ContextResponse: Decodable {
        let suggested_project_name: String?
        let customer_name: String?
        let location: String?
    }

    struct QuestionResponse: Decodable {
        let question: String
        let context: String?
    }

    func toAIEvaluation(measurements: [ARMeasurement]) -> AIEvaluation {
        let mappedServices = services.map { svc in
            let associated = (svc.measurement_indices ?? []).compactMap { idx in
                idx < measurements.count ? measurements[idx] : nil
            }
            return IdentifiedService(
                name: svc.name,
                description: svc.description,
                associatedMeasurements: associated,
                suggestedQuantity: svc.suggested_quantity,
                suggestedUnit: svc.suggested_unit
            )
        }

        let mappedMaterials = materials.map { mat in
            let derived: ARMeasurement? = mat.derived_from_measurement_index.flatMap { idx in
                idx < measurements.count ? measurements[idx] : nil
            }
            return IdentifiedMaterial(
                category: mat.category,
                description: mat.description,
                suggestedQuantity: mat.suggested_quantity,
                suggestedUnit: mat.suggested_unit,
                derivedFromMeasurement: derived
            )
        }

        let mappedContext = context.map {
            OrderContext(
                suggestedProjectName: $0.suggested_project_name,
                suggestedProjectId: nil,
                customerName: $0.customer_name,
                location: $0.location
            )
        }

        let mappedQuestions = open_questions.map {
            OpenQuestion(question: $0.question, context: $0.context)
        }

        return AIEvaluation(
            services: mappedServices,
            materials: mappedMaterials,
            context: mappedContext,
            openQuestions: mappedQuestions
        )
    }
}
