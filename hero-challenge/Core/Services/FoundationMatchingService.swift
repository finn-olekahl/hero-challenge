import Foundation
import FoundationModels

/// Uses Apple's on-device Foundation Models to fuzzy-match AI suggestions
/// against the actual HERO API data (projects, products).
final class FoundationMatchingService: Sendable {

    /// Result of a matching operation — the index into the candidates array (or nil).
    @Generable(description: "The best matching item from a list of candidates")
    struct MatchResult {
        @Guide(description: "The 0-based index of the best matching candidate, or -1 if none match")
        var bestIndex: Int
    }

    /// Attempts to find the best matching project from a list of candidates.
    /// Returns the matched `ProjectMatch` or nil if no good match found.
    func matchProject(
        suggestedName: String,
        customerName: String?,
        candidates: [ProjectMatch]
    ) async -> ProjectMatch? {
        guard !candidates.isEmpty, !suggestedName.isEmpty else { return nil }
        guard SystemLanguageModel.default.isAvailable else { return nil }

        let candidateList = candidates.enumerated().map { i, p in
            let customer = p.customer?.displayName ?? ""
            return "[\(i)] \"\(p.displayName)\" (Kunde: \(customer))"
        }.joined(separator: "\n")

        let session = LanguageModelSession(instructions: """
            Du bist ein Matching-Assistent. \
            Finde das am besten passende Projekt aus der Liste basierend auf dem vorgeschlagenen Namen. \
            Berücksichtige auch den Kundennamen falls angegeben. \
            Wenn kein Projekt gut passt, gib -1 zurück.
            """)

        var prompt = "Vorgeschlagener Projektname: \"\(suggestedName)\""
        if let customerName, !customerName.isEmpty {
            prompt += "\nKundenname: \"\(customerName)\""
        }
        prompt += "\n\nKandidaten:\n\(candidateList)"
        prompt += "\n\nWelcher Kandidat passt am besten?"

        print("🧠 [FoundationMatch] Project prompt:\n\(prompt)")

        do {
            let response = try await session.respond(to: prompt, generating: MatchResult.self)
            let idx = response.content.bestIndex
            print("🧠 [FoundationMatch] Project result index: \(idx)")
            if idx >= 0 && idx < candidates.count {
                print("🧠 [FoundationMatch] Project matched: \"\(candidates[idx].displayName)\"")
                return candidates[idx]
            } else {
                print("🧠 [FoundationMatch] Project index out of range or -1")
            }
        } catch {
            print("⚠️ Foundation Model project matching failed: \(error)")
        }

        return nil
    }

    /// Attempts to find the best matching product for a material category/description.
    /// Uses a two-phase approach: keyword pre-filter first, then Foundation Model as tiebreaker.
    func matchProduct(
        category: String,
        description: String,
        candidates: [SupplyProductVersion],
        transcript: String = ""
    ) async -> SupplyProductVersion? {
        guard !candidates.isEmpty else { return nil }

        // --- Phase 1: keyword pre-filter ---
        let searchTerms = buildSearchTerms(category: category, description: description)
        let scored: [(idx: Int, hits: Int)] = candidates.enumerated().map { idx, product in
            let haystack = "\(product.displayName) \(product.base_data?.description ?? "") \(product.base_data?.manufacturer ?? "")".lowercased()
            let hits = searchTerms.filter { haystack.contains($0) }.count
            return (idx, hits)
        }
        let prefiltered = scored.filter { $0.hits > 0 }.sorted { $0.hits > $1.hits }

        print("🧠 [FoundationMatch] Product pre-filter: \(prefiltered.count) candidates with keyword hits (terms: \(searchTerms))")

        // If exactly 1 match, return directly
        if prefiltered.count == 1 {
            let match = candidates[prefiltered[0].idx]
            print("🧠 [FoundationMatch] Product single keyword match: \"\(match.displayName)\"")
            return match
        }

        // If top candidate has strictly more hits than runner-up, use it
        if prefiltered.count >= 2 && prefiltered[0].hits > prefiltered[1].hits {
            let match = candidates[prefiltered[0].idx]
            print("🧠 [FoundationMatch] Product top keyword match: \"\(match.displayName)\" (\(prefiltered[0].hits) hits vs \(prefiltered[1].hits))")
            return match
        }

        // --- Phase 2: Foundation Model tiebreaker ---
        guard SystemLanguageModel.default.isAvailable else {
            if let best = prefiltered.first {
                let match = candidates[best.idx]
                print("🧠 [FoundationMatch] Product fallback (no LLM): \"\(match.displayName)\"")
                return match
            }
            return nil
        }

        // Use pre-filtered candidates if available, otherwise full list (capped)
        let llmCandidates: [(originalIdx: Int, product: SupplyProductVersion)]
        if !prefiltered.isEmpty {
            llmCandidates = prefiltered.prefix(10).map { (idx: $0.idx, product: candidates[$0.idx]) }
        } else {
            llmCandidates = Array(candidates.prefix(30).enumerated().map { ($0, $1) })
        }

        let candidateList = llmCandidates.enumerated().map { listIdx, pair in
            let p = pair.product
            let desc = p.base_data?.description ?? ""
            let manufacturer = p.base_data?.manufacturer ?? ""
            return "[\(listIdx)] \"\(p.displayName)\" — \(desc) (\(manufacturer))"
        }.joined(separator: "\n")

        let session = LanguageModelSession(instructions: """
            Du bist ein Matching-Assistent für Handwerker-Produkte. \
            Finde das am besten passende Produkt aus der Liste basierend auf Kategorie, Beschreibung \
            und dem Kontext aus dem Transkript des Handwerkers. \
            Achte besonders auf Details wie Farbe, Material, Größe und spezifische Wünsche aus dem Transkript. \
            Wenn kein Produkt gut passt, gib -1 zurück.
            """)

        var prompt = """
            Gesuchte Kategorie: "\(category)"
            Beschreibung: "\(description)"
            """

        if !transcript.isEmpty {
            prompt += "\n\nKontext aus Aufnahme (Transkript):\n\(transcript.prefix(500))"
        }

        prompt += "\n\nProdukt-Kandidaten:\n\(candidateList)"
        prompt += "\n\nWelcher Kandidat passt am besten?"

        print("🧠 [FoundationMatch] Product LLM prompt (\(llmCandidates.count) candidates):\n\(prompt)")

        do {
            let response = try await session.respond(to: prompt, generating: MatchResult.self)
            let idx = response.content.bestIndex
            print("🧠 [FoundationMatch] Product LLM result index: \(idx)")
            if idx >= 0 && idx < llmCandidates.count {
                let match = candidates[llmCandidates[idx].originalIdx]
                print("🧠 [FoundationMatch] Product matched: \"\(match.displayName)\"")
                return match
            } else {
                print("🧠 [FoundationMatch] Product index out of range or -1")
            }
        } catch {
            print("⚠️ Foundation Model product matching failed: \(error)")
        }

        // Last resort: return best keyword match
        if let best = prefiltered.first {
            let match = candidates[best.idx]
            print("🧠 [FoundationMatch] Product keyword fallback after LLM fail: \"\(match.displayName)\"")
            return match
        }

        return nil
    }

    // MARK: - Keyword Extraction

    /// Extracts lowercased search terms from category and description.
    /// Splits on spaces/punctuation, filters short/common words.
    private func buildSearchTerms(category: String, description: String) -> [String] {
        let stopWords: Set<String> = [
            "der", "die", "das", "ein", "eine", "für", "und", "oder", "mit",
            "zum", "zur", "von", "aus", "auf", "bei", "nach", "über", "unter",
            "des", "dem", "den", "ist", "wird", "werden", "hat", "haben",
            "als", "auch", "noch", "wie", "was", "pro", "inkl"
        ]

        let combined = "\(category) \(description)"
        let terms = combined
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopWords.contains($0) }

        // Deduplicate while preserving order
        var seen = Set<String>()
        return terms.filter { seen.insert($0).inserted }
    }
}
