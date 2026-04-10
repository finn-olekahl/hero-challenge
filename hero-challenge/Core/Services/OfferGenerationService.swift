import Foundation

/// Service that uses OpenAI to generate a complete, structured offer
/// from the AI evaluation + questionnaire answers.
final class OfferGenerationService: Sendable {
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

    func generateOffer(
        evaluation: AIEvaluation,
        answers: QuestionnaireController.CollectedAnswers,
        transcript: String
    ) async throws -> GeneratedOffer {
        if let client = openAIClient {
            return try await generateWithOpenAI(
                client: client,
                evaluation: evaluation,
                answers: answers,
                transcript: transcript
            )
        }
        return buildFallbackOffer(evaluation: evaluation, answers: answers)
    }

    // MARK: - OpenAI Generation

    private func generateWithOpenAI(
        client: OpenAIClient,
        evaluation: AIEvaluation,
        answers: QuestionnaireController.CollectedAnswers,
        transcript: String
    ) async throws -> GeneratedOffer {
        let systemPrompt = buildSystemPrompt()
        let userPrompt = buildUserPrompt(
            evaluation: evaluation,
            answers: answers,
            transcript: transcript
        )

        let response: OpenAIOfferResponse = try await client.chatCompletion(
            model: model,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            responseType: OpenAIOfferResponse.self
        )

        return response.toGeneratedOffer()
    }

    private func buildSystemPrompt() -> String {
        """
        Du bist ein KI-Assistent für die HERO Handwerker-Software. \
        Deine Aufgabe ist es, aus den gesammelten Daten ein vollständiges, \
        professionelles Angebot mit konkreten Positionen zu erstellen.

        Du erhältst:
        1. Die ursprüngliche KI-Auswertung (Leistungen, Materialien, Messungen)
        2. Die Antworten des Handwerkers aus dem Fragebogen
        3. Das Original-Transkript der Aufnahme

        Erstelle daraus ein fertiges Angebot mit:

        **Leistungspositionen** (service_positions):
        - Vollständiger Name der Leistung (professionell formuliert)
        - Detaillierte Beschreibung was gemacht wird
        - Korrekte Einheit: NUR diese Werte sind erlaubt: m², Std, lfm, Stk, pauschal, kg, L, m
        - Berechnete Menge aus den bestätigten Mengen / Messungen
        - Netto-Preis pro Einheit: Berechne realistische Marktpreise für Handwerkerleistungen in Deutschland. \
          Nutze als Orientierung: Malerarbeiten ~8-15€/m², Fliesenarbeiten ~30-60€/m², Elektro ~50-70€/Std, \
          Sanitär ~55-75€/Std, Trockenbau ~25-45€/m². Beziehe Materialqualität und Zeitraum ein.

        **Produktpositionen** (product_positions):
        - Name des Produkts (konkreter als die Kategorie)
        - Beschreibung inkl. Spezifikationen
        - Einheit passend zum Katalogprodukt: NUR diese Werte sind erlaubt: m², Std, lfm, Stk, pauschal, kg, L, m
        - Berechnete Menge: Wandle die bestätigte Menge in die Produkteinheit um \
          (z.B. 12m² Fliesen → 12m² als Menge wenn Produkt in m² verkauft wird, \
          oder 45kg Fliesenkleber wenn 3.5kg/m² benötigt)
        - Netto-Preis pro Einheit (falls Kataloginformation vorhanden, sonst 0)
        - catalog_product_id: Falls ein konkretes Katalogprodukt gewählt wurde

        **WICHTIG zu Einheiten:**
        - Verwende NIEMALS "psch" – der korrekte Wert ist "pauschal"
        - Verwende NIEMALS "l" – der korrekte Wert ist "L" (großes L)

        **Wichtige Regeln:**
        - Verwende die VOM HANDWERKER BESTÄTIGTEN Mengen, nicht die KI-Vorschläge
        - Passe Einheiten an: Wenn der Handwerker 12m² bestätigt hat und das Produkt in kg verkauft wird, \
          rechne um (z.B. Fliesenkleber: 12m² × 3.5kg/m² = 42kg)
        - Füge Verschnitt/Puffer hinzu wo branchenüblich (nur bei Material, nicht bei Leistungen)
        - Berücksichtige Antworten auf offene Fragen (Materialqualität, Entsorgung etc.)
        - Der Zeitraum-Wunsch fließt ggf. in die Beschreibung ein
        - Erstelle eine kurze Angebotsnotiz (notes) mit Randbedingungen/Hinweisen
        - Alle Texte auf Deutsch, professionelle Handwerker-Sprache

        Antworte ausschließlich als JSON:
        {
          "title": "Angebotstitel",
          "description": "Kurze Angebotsbeschreibung",
          "service_positions": [
            {
              "name": "string",
              "description": "string",
              "unit_type": "m²",
              "quantity": 12.0,
              "net_price_per_unit": 35.00
            }
          ],
          "product_positions": [
            {
              "name": "string",
              "description": "string",
              "unit_type": "Stk",
              "quantity": 5.0,
              "net_price": 12.50,
              "catalog_product_id": "string oder null"
            }
          ],
          "notes": "string oder null"
        }
        """
    }

    private func buildUserPrompt(
        evaluation: AIEvaluation,
        answers: QuestionnaireController.CollectedAnswers,
        transcript: String
    ) -> String {
        var prompt = "## Original-Transkript\n\(transcript)\n\n"

        // Evaluation data
        prompt += "## Erkannte Leistungen\n"
        for service in evaluation.services {
            prompt += "- \(service.name): \(service.description)"
            if let qty = service.suggestedQuantity, let unit = service.suggestedUnit {
                prompt += " (vorgeschlagen: \(String(format: "%.1f", qty)) \(unit))"
            }
            if !service.associatedMeasurements.isEmpty {
                let mStr = service.associatedMeasurements.map { $0.formattedValue }.joined(separator: ", ")
                prompt += " [Messungen: \(mStr)]"
            }
            prompt += "\n"
        }

        prompt += "\n## Erkannte Materialien\n"
        for material in evaluation.materials {
            prompt += "- \(material.category): \(material.description)"
            if let qty = material.suggestedQuantity, let unit = material.suggestedUnit {
                prompt += " (vorgeschlagen: \(String(format: "%.1f", qty)) \(unit))"
            }
            prompt += "\n"
        }

        // Questionnaire answers
        prompt += "\n## Fragebogen-Antworten\n"

        prompt += "\n### Abrechnungsmethoden\n"
        for billing in answers.billingMethods {
            let methodStr: String
            switch billing.method {
            case .hourly(let h): methodStr = "Nach Stunden (\(String(format: "%.1f", h)) Std)"
            case .serviceType(let s): methodStr = s != nil ? "Leistungstyp: \(s!.displayName)" : "Leistungstyp (nicht gewählt)"
            case .unselected: methodStr = "Nicht festgelegt"
            }
            prompt += "- \(billing.service.name): \(methodStr)\n"
        }

        prompt += "\n### Gewählte Produkte\n"
        for product in answers.selectedProducts {
            if let p = product.product {
                prompt += "- \(product.material.category) → \(p.displayName)"
                if let unit = p.unit { prompt += " (Einheit: \(unit))" }
                if let price = p.price_net { prompt += " (Netto: \(String(format: "%.2f", price))€)" }
                prompt += "\n"
            } else {
                prompt += "- \(product.material.category) → kein Produkt gewählt\n"
            }
        }

        if !answers.confirmedQuantities.isEmpty {
            prompt += "\n### Bestätigte Mengen\n"
            for qty in answers.confirmedQuantities {
                let unitStr = qty.unit.isEmpty ? "" : " \(qty.unit)"
                prompt += "- \(qty.label): \(String(format: "%.1f", qty.quantity))\(unitStr)\n"
            }
        }

        if !answers.timeframe.isEmpty {
            prompt += "\n### Gewünschter Zeitraum\n\(answers.timeframe)\n"
        }

        if !answers.freeTextAnswers.isEmpty {
            prompt += "\n### Weitere Angaben\n"
            for answer in answers.freeTextAnswers {
                if !answer.answer.isEmpty {
                    prompt += "- \(answer.question): \(answer.answer)\n"
                }
            }
        }

        return prompt
    }

    // MARK: - Fallback (no API key)

    private func buildFallbackOffer(
        evaluation: AIEvaluation,
        answers: QuestionnaireController.CollectedAnswers
    ) -> GeneratedOffer {
        var servicePositions: [GeneratedServicePosition] = []
        var productPositions: [GeneratedProductPosition] = []

        for billing in answers.billingMethods {
            let qty: Double
            let unit: String
            switch billing.method {
            case .hourly(let h):
                qty = max(h, 1)
                unit = "Std"
            case .serviceType:
                qty = billing.service.suggestedQuantity ?? 1
                unit = billing.service.suggestedUnit ?? "Stk"
            case .unselected:
                qty = billing.service.suggestedQuantity ?? 1
                unit = billing.service.suggestedUnit ?? "Stk"
            }
            servicePositions.append(GeneratedServicePosition(
                name: billing.service.name,
                description: billing.service.description,
                unitType: unit,
                quantity: qty,
                netPricePerUnit: 0
            ))
        }

        for productEntry in answers.selectedProducts {
            if let product = productEntry.product {
                productPositions.append(GeneratedProductPosition(
                    name: product.displayName,
                    description: productEntry.material.description,
                    unitType: product.unit ?? productEntry.material.suggestedUnit ?? "Stk",
                    quantity: productEntry.material.suggestedQuantity ?? 1,
                    netPrice: product.price_net ?? 0,
                    catalogProductId: product.product_id
                ))
            }
        }

        return GeneratedOffer(
            title: evaluation.context?.suggestedProjectName ?? "Angebot",
            description: "Angebot basierend auf Vor-Ort-Aufnahme",
            servicePositions: servicePositions,
            productPositions: productPositions,
            notes: nil
        )
    }
}

// MARK: - OpenAI Response Mapping

private struct OpenAIOfferResponse: Decodable {
    let title: String
    let description: String
    let service_positions: [ServicePositionResponse]
    let product_positions: [ProductPositionResponse]
    let notes: String?

    struct ServicePositionResponse: Decodable {
        let name: String
        let description: String
        let unit_type: String
        let quantity: Double
        let net_price_per_unit: Double
    }

    struct ProductPositionResponse: Decodable {
        let name: String
        let description: String
        let unit_type: String
        let quantity: Double
        let net_price: Double
        let catalog_product_id: String?
    }

    func toGeneratedOffer() -> GeneratedOffer {
        GeneratedOffer(
            title: title,
            description: description,
            servicePositions: service_positions.map {
                GeneratedServicePosition(
                    name: $0.name,
                    description: $0.description,
                    unitType: $0.unit_type,
                    quantity: $0.quantity,
                    netPricePerUnit: $0.net_price_per_unit
                )
            },
            productPositions: product_positions.map {
                GeneratedProductPosition(
                    name: $0.name,
                    description: $0.description,
                    unitType: $0.unit_type,
                    quantity: $0.quantity,
                    netPrice: $0.net_price,
                    catalogProductId: $0.catalog_product_id
                )
            },
            notes: notes
        )
    }
}
