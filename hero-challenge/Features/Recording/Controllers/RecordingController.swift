import Foundation
import Observation
import UIKit

/// Recording state machine.
enum RecordingState {
    case idle
    case recording
    case paused
    case processing
    case clarification  // waiting for user to answer pre-scan questions
    case evaluating     // running full analysis after clarification
    case completed
}

/// Central controller for the AI recording session.
/// Orchestrates speech recognition, photo capture, AR measurement, and timeline.
@Observable
final class RecordingController {
    // MARK: - State

    private(set) var state: RecordingState = .idle
    private(set) var timeline: RecordingTimeline = RecordingTimeline()
    private(set) var capturedPhotos: [CapturedPhoto] = []
    private(set) var currentTranscript: String = ""
    private(set) var elapsedTime: TimeInterval = 0
    private(set) var evaluation: AIEvaluation?
    private(set) var pendingQuestions: [OpenQuestion] = []
    private(set) var errorMessage: String?

    let measureController = MeasureController()

    // MARK: - Dependencies

    private let speechService = SpeechRecognitionService()
    private let aiService = AIEvaluationService()
    private var recordingStartTime: Date?
    private var timer: Timer?
    private var accumulatedTimeBeforePause: TimeInterval = 0
    private var lastResumeTime: Date?

    // MARK: - Computed

    var hasError: Bool { errorMessage != nil }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - State Queries

    var isActive: Bool { state == .recording || state == .paused }
    var measurementCount: Int { timeline.entries.filter { $0.type == .measurement }.count }
    var photoCount: Int { capturedPhotos.count }

    var formattedElapsedTime: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    init() {
        measureController.onMeasurementCompleted = { [weak self] measurement in
            self?.addMeasurement(measurement)
        }
        measureController.onMeasurementsRevoked = { [weak self] ids in
            self?.removeMeasurements(ids: ids)
        }
    }

    // MARK: - Actions

    func startRecording() async {
        guard state == .idle else { return }

        let authorized = await speechService.requestAuthorization()
        guard authorized else {
            errorMessage = "Spracherkennung nicht autorisiert. Bitte in den Einstellungen aktivieren."
            return
        }

        recordingStartTime = Date()
        timeline = RecordingTimeline(startedAt: recordingStartTime!)
        capturedPhotos = []
        currentTranscript = ""
        elapsedTime = 0
        evaluation = nil
        errorMessage = nil
        accumulatedTimeBeforePause = 0
        lastResumeTime = recordingStartTime

        speechService.onTranscript = { [weak self] text, timestamp in
            guard let self else { return }
            self.currentTranscript = text
        }

        speechService.onSegmentsFinalized = { [weak self] segments in
            guard let self else { return }
            self.timeline.addSegments(segments)
        }

        do {
            try await speechService.startRecording(startTime: recordingStartTime!)
            state = .recording
            startTimer()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pauseRecording() {
        guard state == .recording else { return }
        speechService.pauseRecording()
        stopTimer()
        if let resume = lastResumeTime {
            accumulatedTimeBeforePause += Date().timeIntervalSince(resume)
        }
        state = .paused
    }

    func resumeRecording() {
        guard state == .paused else { return }
        do {
            try speechService.resumeRecording()
            lastResumeTime = Date()
            state = .recording
            startTimer()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopRecording() async {
        guard state == .recording || state == .paused else { return }
        speechService.stopRecording()
        stopTimer()
        state = .processing

        do {
            // Phase 1: Pre-scan for clarifying questions
            let questions = try await aiService.prescan(timeline: timeline, photos: capturedPhotos)
            if questions.isEmpty {
                // No questions → proceed directly to full evaluation
                let result = try await aiService.evaluate(timeline: timeline, photos: capturedPhotos)
                evaluation = result
                state = .completed
            } else {
                // Has questions → pause for clarification
                pendingQuestions = questions
                state = .clarification
            }
        } catch {
            errorMessage = error.localizedDescription
            state = .processing // stay in processing so retry is possible
        }
    }

    /// Submit clarification answers and run full evaluation.
    func submitClarifications(_ answers: [(question: String, answer: String)]) async {
        state = .evaluating
        do {
            let result = try await aiService.evaluate(
                timeline: timeline,
                photos: capturedPhotos,
                clarifications: answers
            )
            evaluation = result
            state = .completed
        } catch {
            errorMessage = error.localizedDescription
            state = .evaluating
        }
    }

    /// Skip clarification and proceed with evaluation without answers.
    func skipClarifications() async {
        state = .evaluating
        do {
            let result = try await aiService.evaluate(timeline: timeline, photos: capturedPhotos)
            evaluation = result
            state = .completed
        } catch {
            errorMessage = error.localizedDescription
            state = .evaluating
        }
    }

    func retryEvaluation() async {
        guard state == .processing || state == .evaluating else { return }
        errorMessage = nil
        do {
            let result = try await aiService.evaluate(timeline: timeline, photos: capturedPhotos)
            evaluation = result
            state = .completed
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func capturePhoto(_ image: UIImage) {
        guard isActive else { return }
        let timestamp = Date().timeIntervalSince(recordingStartTime ?? Date())
        let photo = CapturedPhoto(image: image, timestamp: timestamp)
        capturedPhotos.append(photo)
        timeline.addPhoto(id: photo.id, at: timestamp)
    }

    func reset() {
        speechService.stopRecording()
        stopTimer()
        state = .idle
        timeline = RecordingTimeline()
        capturedPhotos = []
        currentTranscript = ""
        elapsedTime = 0
        evaluation = nil
        pendingQuestions = []
        errorMessage = nil
        accumulatedTimeBeforePause = 0
        lastResumeTime = nil
        measureController.clear()
    }

    // MARK: - Private

    private func addMeasurement(_ measurement: ARMeasurement) {
        let timestamp = Date().timeIntervalSince(recordingStartTime ?? Date())
        timeline.addMeasurement(measurement, at: timestamp)
    }

    private func removeMeasurements(ids: [UUID]) {
        timeline.removeMeasurements(withIDs: Set(ids))
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let resume = self.lastResumeTime else { return }
            self.elapsedTime = self.accumulatedTimeBeforePause + Date().timeIntervalSince(resume)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
