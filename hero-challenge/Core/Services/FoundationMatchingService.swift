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
    /// Uses keyword scoring + Foundation Model for best results.
    func matchProject(
        suggestedName: String,
        customerName: String?,
        candidates: [ProjectMatch]
    ) async -> ProjectMatch? {
        guard !candidates.isEmpty, !suggestedName.isEmpty else { return nil }

        // --- Phase 1: keyword scoring ---
        let searchTerms = buildSearchTerms(category: suggestedName, description: customerName ?? "")
        let scored: [(idx: Int, score: Int)] = candidates.enumerated().map { idx, project in
            let projectName = project.displayName.lowercased()
            let customerStr = project.customer?.displayName.lowercased() ?? ""
            let haystack = "\(projectName) \(customerStr)"

            var score = 0
            for term in searchTerms {
                if haystack.contains(term) { score += 2 }
                // Fuzzy: check if any word in haystack starts with the same 4+ chars
                let haystackWords = haystack.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 3 }
                for word in haystackWords {
                    if term.count >= 4 && word.count >= 4 {
                        let prefixLen = min(4, min(term.count, word.count))
                        if term.prefix(prefixLen) == word.prefix(prefixLen) && !haystack.contains(term) {
                            score += 1 // partial match (e.g. "meyer" vs "meier")
                        }
                    }
                }
            }
            // Bonus: customer name exact substring match
            if let cn = customerName?.lowercased(), !cn.isEmpty, customerStr.contains(cn) {
                score += 5
            }
            return (idx, score)
        }

        let ranked = scored.filter { $0.score > 0 }.sorted { $0.score > $1.score }

        if (ranked.count == 1 && ranked[0].score >= 3) || (ranked.count >= 2 && ranked[0].score >= 4 && ranked[0].score > ranked[1].score * 2) {
        if (ranked.count == 1 && ranked[0].score >= 3) || (ranked.count >= 2 && ranked[0].score >= 4 && ranked[0].score > ranked[1].score * 2) {
            let match = candidates[ranked[0].idx]
            return match
        }
        guard SystemLanguageModel.default.isAvailable else {
            if let best = ranked.first, best.score >= 3 {
                return candidates[best.idx]
            }
            return nil
        }

        let llmCandidates: [(originalIdx: Int, project: ProjectMatch)]
        if !ranked.isEmpty {
            llmCandidates = ranked.prefix(8).map { (idx: $0.idx, project: candidates[$0.idx]) }
        } else {
            llmCandidates = Array(candidates.prefix(15).enumerated().map { ($0, $1) })
        }

        let candidateList = llmCandidates.enumerated().map { listIdx, pair in
            let p = pair.project
            let customer = p.customer?.displayName ?? ""
            return "[\(listIdx)] \"\(p.displayName)\" (Kunde: \(customer))"
        }.joined(separator: "\n")

        let session = LanguageModelSession(instructions: """
            Du bist ein Matching-Assistent für Handwerker-Projekte. \
            Finde das am besten passende Projekt basierend auf dem vorgeschlagenen Namen und Kundennamen. \
            Beachte: Kundennamen können leicht abweichen (Meyer/Meier/Maier, Schmidt/Schmitt etc.). \
            WICHTIG: Rate nicht. Wenn kein Kandidat eindeutig zum Namen oder Kunden passt, musst du zwingend -1 zurückgeben. \
            Priorisiere Übereinstimmung beim Kundennamen höher als beim Projektnamen.
            """)

        var prompt = "Vorgeschlagener Projektname: \"\(suggestedName)\""
        if let customerName, !customerName.isEmpty {
            prompt += "\nKundenname aus Aufnahme: \"\(customerName)\""
        }
        prompt += "\n\nKandidaten:\n\(candidateList)"
        prompt += "\n\nWelcher Kandidat passt am besten?"

        do {
            let response = try await session.respond(to: prompt, generating: MatchResult.self)
            let idx = response.content.bestIndex
            if idx >= 0 && idx < llmCandidates.count {
                let match = candidates[llmCandidates[idx].originalIdx]
                return match
            }
        } catch {
        }

        if let best = ranked.first, best.score >= 3 {
            return candidates[best.idx]
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

        let searchTerms = buildSearchTerms(category: category, description: description)
        let transcriptTerms = buildSearchTerms(category: "", description: transcript)
        let colorTerms = extractColorTerms(from: "\(category) \(description) \(transcript)")

        let scored: [(idx: Int, score: Int)] = candidates.enumerated().map { idx, product in
            let name = product.displayName.lowercased()
            let desc = (product.base_data?.description ?? "").lowercased()
            let manufacturer = (product.base_data?.manufacturer ?? "").lowercased()
            let haystack = "\(name) \(desc) \(manufacturer)"

            var score = 0

            let categoryTerms = buildSearchTerms(category: category, description: "")
            for term in categoryTerms {
                if haystack.contains(term) { score += 3 }
            }

            for term in searchTerms where !categoryTerms.contains(term) {
                if haystack.contains(term) { score += 2 }
            }

            for color in colorTerms {
                if haystack.contains(color) { score += 4 }
            }

            let categoryLower = category.lowercased()
            if haystack.contains(categoryLower) { score += 5 }

            for term in transcriptTerms {
                if haystack.contains(term) { score += 1 }
            }

            return (idx, score)
        }

        let prefiltered = scored.filter { $0.score > 0 }.sorted { $0.score > $1.score }

        if prefiltered.count == 1 && prefiltered[0].score >= 4 {
            let match = candidates[prefiltered[0].idx]
            return match
        }

        if prefiltered.count >= 2 && prefiltered[0].score >= 5 && prefiltered[0].score > prefiltered[1].score + 2 {
            let match = candidates[prefiltered[0].idx]
            return match
        }
        guard SystemLanguageModel.default.isAvailable else {
            if let best = prefiltered.first, best.score >= 4 {
                let match = candidates[best.idx]
                return match
            }
            return nil
        }

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
            Finde das am besten passende Produkt aus der Liste. \
            WICHTIG: Rate nicht. Wenn kein Kandidat eindeutig zur gesuchten Kategorie und Beschreibung passt, musst du zwingend -1 zurückgeben. \
            Priorisiere: 1. Passende Produktkategorie, 2. Farbe/Variante, 3. Beschreibung. \
            Achte besonders auf Details wie Farbe (weiß/rot/etc.), Material, Größe.
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

        do {
            let response = try await session.respond(to: prompt, generating: MatchResult.self)
            let idx = response.content.bestIndex
            if idx >= 0 && idx < llmCandidates.count {
                let match = candidates[llmCandidates[idx].originalIdx]
                return match
            }
        } catch {
        }

        if let best = prefiltered.first, best.score >= 4 {
            let match = candidates[best.idx]
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
            "als", "auch", "noch", "wie", "was", "pro", "inkl", "soll",
            "weiße", "weisse", "rote", "blaue", "schwarze", "graue" // colors handled separately
        ]

        let combined = "\(category) \(description)"
        let terms = combined
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "äöüß")).inverted)
            .filter { $0.count >= 3 && !stopWords.contains($0) }

        // Deduplicate while preserving order
        var seen = Set<String>()
        return terms.filter { seen.insert($0).inserted }
    }

    /// Extracts color keywords from text for product matching.
    private func extractColorTerms(from text: String) -> [String] {
        let colorMap: [(patterns: [String], normalized: String)] = [
            (["weiß", "weiss", "weiße", "weisse", "white"], "weiß"),
            (["rot", "rote", "red"], "rot"),
            (["blau", "blaue", "blue"], "blau"),
            (["grün", "grüne", "green"], "grün"),
            (["schwarz", "schwarze", "black"], "schwarz"),
            (["grau", "graue", "grey", "gray"], "grau"),
            (["gelb", "gelbe", "yellow"], "gelb"),
            (["braun", "braune", "brown"], "braun"),
        ]

        let lower = text.lowercased()
        var found: [String] = []
        for color in colorMap {
            if color.patterns.contains(where: { lower.contains($0) }) {
                found.append(color.normalized)
            }
        }
        return found
    }
}
