import Foundation

/// Service that processes the recording timeline and produces a structured AI evaluation.
/// Uses OpenAI Chat Completions when configured, falls back to keyword-based mock otherwise.
final class AIEvaluationService: Sendable {
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

    // MARK: - Phase 1: Pre-scan for clarifying questions

    /// Quick pre-scan of the recording to check if anything is genuinely unclear.
    /// Returns questions only when the transcript is truly ambiguous or incomprehensible.
    func prescan(timeline: RecordingTimeline, photos: [CapturedPhoto]) async throws -> [OpenQuestion] {
        guard let client = openAIClient else { return [] }

        let measurements = timeline.entries.compactMap { $0.content.measurementValue }
        let userPrompt = buildUserPrompt(timeline: timeline, measurements: measurements, photos: photos)

        let systemPrompt = """
        Du bist ein KI-Assistent für die HERO Handwerker-Software. \
        Ein Handwerker hat vor Ort eine Aufnahme gemacht (Sprache, Fotos, Messungen). \
        Deine EINZIGE Aufgabe: Prüfe, ob das Transkript so unklar oder widersprüchlich ist, \
        dass du die gewünschten Arbeiten NICHT identifizieren kannst.

        WICHTIG:
        - Du sprichst mit einem FACHMANN. Stelle KEINE fachlichen Fragen \
          (Wandvorbereitung, Materialqualität, Untergrund, Entsorgung etc.).
        - Stelle KEINE Fragen zu Dingen, die der Handwerker selbst entscheiden kann.
        - Stelle KEINE Fragen zu konkreten Produkten, Mengen, Zeiträumen oder Preisen.
        - Frage NUR, wenn du aus dem Transkript nicht verstehen kannst, \
          WAS gemacht werden soll oder WO gearbeitet werden soll.
        - Im Normalfall gibt es KEINE Fragen. Nur bei echten Verständnisproblemen.

        Beispiele für ERLAUBTE Fragen (nur wenn wirklich unklar):
        - "Im Transkript wird 'das da oben' erwähnt – ist damit die Decke oder die obere Wandhälfte gemeint?"
        - "Es werden zwei Räume erwähnt aber nur eine Messung – gilt die Messung für beide?"

        Beispiele für VERBOTENE Fragen (NIEMALS stellen):
        - "Welche Qualität der Wandfarbe wird gewünscht?"
        - "Ist die Wandoberfläche bereits vorbereitet?"
        - "Soll Altbelag entfernt werden?"
        - "Wie ist der Zugang zur Baustelle?"

        Antworte als JSON:
        {
          "questions": [
            { "question": "string", "context": "string" }
          ]
        }

        Wenn alles klar ist (Normalfall), antworte mit:
        { "questions": [] }
        """

        let response: PrescanResponse = try await client.chatCompletion(
            model: model,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            responseType: PrescanResponse.self
        )

        return response.questions.map { OpenQuestion(question: $0.question, context: $0.context) }
    }

    // MARK: - Phase 2: Full evaluation

    func evaluate(
        timeline: RecordingTimeline,
        photos: [CapturedPhoto],
        clarifications: [(question: String, answer: String)] = []
    ) async throws -> AIEvaluation {
        let fullTranscript = timeline.fullTranscript
        let measurements = timeline.entries.compactMap { $0.content.measurementValue }

        if let client = openAIClient {
            return try await evaluateWithOpenAI(
                client: client,
                timeline: timeline,
                measurements: measurements,
                photos: photos,
                clarifications: clarifications
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
        timeline: RecordingTimeline,
        measurements: [ARMeasurement],
        photos: [CapturedPhoto],
        clarifications: [(question: String, answer: String)]
    ) async throws -> AIEvaluation {
        let systemPrompt = buildSystemPrompt()
        var userPrompt = buildUserPrompt(
            timeline: timeline,
            measurements: measurements,
            photos: photos
        )

        if !clarifications.isEmpty {
            userPrompt += "\n## Klärungen\n"
            for c in clarifications {
                userPrompt += "Frage: \(c.question)\nAntwort: \(c.answer)\n\n"
            }
        }

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
        eines Handwerkers vor Ort ein strukturiertes Dokument vorzubereiten.

        **SCHRITT 1: Erkenne die Absicht (intent)**
        Bestimme aus dem Transkript, was der Handwerker erstellen möchte:
        - "offer" — Ein Angebot für bevorstehende Arbeiten (Handwerker plant/bespricht Arbeiten, \
          misst aus, bespricht mit Kunden was gemacht werden soll)
        - "work_report" — Ein Arbeitsbericht über abgeschlossene Arbeiten (Handwerker dokumentiert \
          was er getan hat, welche Materialien er verbraucht hat, Ergebnisse, Arbeitsstunden)
        - "site_report" — Ein Baustellenbericht zur Fortschrittsdokumentation (Handwerker dokumentiert \
          aktuellen Baustellenzustand, macht Fotos zur Dokumentation, beschreibt Fortschritt/Probleme)

        Hinweise zur Erkennung (in Prioritätsreihenfolge):
        1. **Explizite Nennung hat HÖCHSTE Priorität:**
           - Sagt der Handwerker "Baustellenbericht" → site_report
           - Sagt der Handwerker "Arbeitsbericht" → work_report
           - Sagt der Handwerker "Angebot" → offer
        2. Nur wenn KEIN Dokumenttyp explizit genannt wird, nutze diese Heuristiken:
           - Vergangenheitsform ("habe gestrichen", "wurde verlegt") → eher work_report
           - Zukunftsform ("soll gemacht werden", "muss noch") → eher offer
           - Dokumentationssprache ("aktueller Stand", "Fortschritt", "Zustand") → eher site_report
           - Erwähnung von Preisen, Kalkulation → offer
           - Erwähnung von verbrauchten Materialien, Stunden → work_report
        3. Bei Unklarheit: Standardmäßig "offer"

        **SCHRITT 2: Analysiere den Inhalt**
        1. **Leistungen** (services): Welche Arbeiten sollen/wurden durchgeführt?
        2. **Materialien** (materials): Welche Materialien / Artikelkategorien werden benötigt / wurden verbraucht? \
           Gib keine konkreten Produkte an, sondern Kategorien (z.B. "Fliesen", "Wandfarbe").
        3. **Auftragskontext** (context): Kundenname, Projektname, Ort.
           - **suggested_project_name**: Schlage IMMER einen Projektnamen vor, auch wenn keiner explizit genannt wurde. \
             Leite den Namen aus den erkannten Leistungen, dem Ort oder dem Kundenkontext ab \
             (z.B. "Badsanierung Müller", "Fliesenarbeiten Küche", "Malerarbeiten EG"). \
             Nur null wenn das Transkript komplett leer oder unverständlich ist.

        Falls im User-Prompt ein Abschnitt "## Klärungen" enthalten ist, nutze diese Antworten als zusätzlichen Kontext.

        Verknüpfe Messungen mit den passenden Leistungen und Materialien. \
        Berechne vorgeschlagene Mengen aus den Messungen (z.B. Fläche + 10% Verschnitt für Fliesen).

        Antworte ausschließlich als JSON-Objekt mit folgendem Schema:
        {
          "intent": "offer | work_report | site_report",
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
          "open_questions": []
        }

        Regeln:
        - open_questions ist IMMER ein leeres Array. Stelle KEINE Fragen.
        - measurement_indices bezieht sich auf den Index in der Messungsliste (0-basiert).
        - derived_from_measurement_index: Index der Messung, aus der die Menge abgeleitet wurde, oder null.
        - Wenn keine spezifischen Leistungen erkannt werden, erstelle eine generische "Handwerkerleistung".
        - suggested_project_name MUSS immer gesetzt sein. Erstelle einen kurzen, beschreibenden Namen \
          aus den Leistungen und ggf. Kundenname/Ort (z.B. "Badsanierung", "Elektroarbeiten Neubau", "Fliesenarbeiten Schmidt").
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

    private func buildUserPrompt(
        timeline: RecordingTimeline,
        measurements: [ARMeasurement],
        photos: [CapturedPhoto]
    ) -> String {
        var items: [(time: TimeInterval, text: String)] = []

        for segment in timeline.transcriptSegments {
            items.append((
                segment.startTime,
                "[\(formatTime(segment.startTime))–\(formatTime(segment.endTime))] \"\(segment.text)\""
            ))
        }

        for (i, photo) in photos.enumerated() {
            items.append((photo.timestamp, "[\(formatTime(photo.timestamp))] Foto \(i + 1)"))
        }

        var measurementIndex = 0
        for entry in timeline.entries {
            guard let m = entry.content.measurementValue else { continue }
            let typeDesc = m.type == .area ? "Fläche" : "Länge"
            items.append((entry.timestamp, "[\(formatTime(entry.timestamp))] Messung [\(measurementIndex)]: \(typeDesc) \(m.formattedValue)"))
            measurementIndex += 1
        }

        items.sort { $0.time < $1.time }

        var prompt = "## Aufnahme-Timeline\n"
        for item in items {
            prompt += item.text + "\n"
        }

        if !measurements.isEmpty {
            prompt += "\n## Messungen (Index-Referenz)\n"
            for (i, m) in measurements.enumerated() {
                let typeDesc = m.type == .area ? "Flächenmessung" : "Längenmessung"
                prompt += "[\(i)] \(typeDesc): \(m.formattedValue)\n"
            }
        }

        prompt += "\n## Fotos\n\(photos.count) Foto(s) aufgenommen.\n"

        return prompt
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
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
            intent: .offer,
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

// MARK: - Prescan Response

private struct PrescanResponse: Decodable {
    let questions: [PrescanQuestion]

    struct PrescanQuestion: Decodable {
        let question: String
        let context: String?
    }
}

// MARK: - OpenAI Response Mapping

/// Decodable shape matching the JSON schema we ask OpenAI to return.
private struct OpenAIEvaluationResponse: Decodable {
    let intent: String?
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

        let detectedIntent = DocumentIntent(rawValue: intent ?? "offer") ?? .offer

        return AIEvaluation(
            intent: detectedIntent,
            services: mappedServices,
            materials: mappedMaterials,
            context: mappedContext,
            openQuestions: mappedQuestions
        )
    }
}
