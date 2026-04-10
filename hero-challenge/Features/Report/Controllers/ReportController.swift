import Foundation
import Observation
import UIKit

/// Controller that generates a report via AI, uploads photos, and creates a logbook entry via the HERO API.
@Observable
final class ReportController {
    private(set) var isGenerating = false
    private(set) var isUploading = false
    private(set) var isCreating = false
    private(set) var isCompleted = false
    private(set) var errorMessage: String?
    private(set) var generatedReport: GeneratedReport?
    private(set) var uploadProgress: Double = 0

    private let apiService: HeroAPIService
    private let reportGenService = ReportGenerationService()
    let intent: DocumentIntent
    let evaluation: AIEvaluation
    let answers: QuestionnaireController.CollectedAnswers
    let photos: [CapturedPhoto]
    let transcript: String

    var isWorking: Bool { isGenerating || isUploading || isCreating }

    var reportTitle: String {
        switch intent {
        case .workReport: return "Arbeitsbericht"
        case .siteReport: return "Baustellenbericht"
        case .offer: return "Bericht"
        }
    }

    init(
        intent: DocumentIntent,
        evaluation: AIEvaluation,
        answers: QuestionnaireController.CollectedAnswers,
        photos: [CapturedPhoto],
        apiService: HeroAPIService,
        transcript: String = ""
    ) {
        self.intent = intent
        self.evaluation = evaluation
        self.answers = answers
        self.photos = photos
        self.apiService = apiService
        self.transcript = transcript
    }

    // MARK: - Generate Report via AI

    func generateReport() async {
        guard !isGenerating else { return }
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        let measurements = evaluation.services.flatMap(\.associatedMeasurements)

        do {
            let report = try await reportGenService.generateReport(
                intent: intent,
                evaluation: evaluation,
                answers: answers,
                transcript: transcript,
                photoCount: photos.count,
                measurements: measurements
            )
            generatedReport = report
        } catch {
            errorMessage = "KI-Generierung fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    // MARK: - Create via API (upload photos + logbook entry)

    func createReport() async {
        guard !isCreating, let report = generatedReport else { return }
        isCreating = true
        isUploading = true
        errorMessage = nil

        do {
            guard let project = answers.project else {
                errorMessage = "Kein Projekt ausgewählt."
                isCreating = false
                isUploading = false
                return
            }

            // Step 1: Upload all photos and collect UUIDs
            var uploadedUUIDs: [String] = []
            for (i, photo) in photos.enumerated() {
                guard let imageData = photo.image.jpegData(compressionQuality: 0.8) else { continue }
                let filename = "foto_\(i + 1)_\(Int(Date().timeIntervalSince1970)).jpg"
                let uuid = try await apiService.uploadImage(imageData, filename: filename)
                uploadedUUIDs.append(uuid)
                uploadProgress = Double(i + 1) / Double(photos.count)
            }
            isUploading = false

            // Step 2: Link uploaded images to the project
            for uuid in uploadedUUIDs {
                _ = try await apiService.linkImageToProject(
                    fileUploadUUID: uuid,
                    projectMatchId: project.id
                )
            }

            // Step 3: Build rich text HTML with embedded photo references
            let htmlContent = buildHTMLContent(report: report, photoUUIDs: uploadedUUIDs)

            // Step 4: Create logbook entry
            _ = try await apiService.addLogbookEntry(
                projectMatchId: project.id,
                text: htmlContent
            )

            isCompleted = true
        } catch let error as GraphQLError {
            switch error {
            case .httpError(let code, let body):
                if code == 200 {
                    // GraphQL-level error — show the actual message
                    errorMessage = "API-Fehler: \(body)"
                } else {
                    errorMessage = "Serverfehler (HTTP \(code)). Bitte erneut versuchen."
                }
            default:
                errorMessage = "Fehler: \(error.localizedDescription)"
            }
        } catch {
            errorMessage = "Fehler: \(error.localizedDescription)"
        }

        isCreating = false
        isUploading = false
    }

    // MARK: - HTML Building

    private func buildHTMLContent(report: GeneratedReport, photoUUIDs: [String]) -> String {
        var html = "<h1>\(escapeHTML(report.title))</h1>\n"
        html += "<p><em>\(escapeHTML(report.summary))</em></p>\n"

        let measurements = evaluation.services.flatMap(\.associatedMeasurements)

        for section in report.sections {
            html += "<h2>\(escapeHTML(section.heading))</h2>\n"
            // Convert body paragraphs
            let paragraphs = section.body.components(separatedBy: "\n\n")
            for para in paragraphs {
                let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    html += "<p>\(escapeHTML(trimmed))</p>\n"
                }
            }

            // Embed measurements
            if !section.measurementIndices.isEmpty {
                html += "<table border=\"1\" cellpadding=\"4\" cellspacing=\"0\">\n"
                html += "<tr><th>Messung</th><th>Typ</th><th>Wert</th></tr>\n"
                for idx in section.measurementIndices where idx < measurements.count {
                    let m = measurements[idx]
                    let typeStr = m.type == .area ? "Fläche" : "Länge"
                    html += "<tr><td>Messung \(idx + 1)</td><td>\(typeStr)</td><td>\(m.formattedValue)</td></tr>\n"
                }
                html += "</table>\n"
            }

            // Embed photos
            for idx in section.photoIndices where idx < photoUUIDs.count {
                let uuid = photoUUIDs[idx]
                html += "<p><strong>Foto \(idx + 1):</strong></p>\n"
                html += "<p><img src=\"/api/file_uploads/\(escapeHTML(uuid))\" alt=\"Foto \(idx + 1)\" style=\"max-width:100%;\"/></p>\n"
            }
        }

        return html
    }

    private func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Summary of report content for the review screen.
    var reportSummary: ReportSummary {
        ReportSummary(
            projectName: answers.project?.displayName ?? "—",
            sectionCount: generatedReport?.sections.count ?? 0,
            photoCount: photos.count,
            title: generatedReport?.title
        )
    }
}

struct ReportSummary {
    let projectName: String
    let sectionCount: Int
    let photoCount: Int
    let title: String?
}
