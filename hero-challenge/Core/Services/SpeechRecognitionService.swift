import Foundation
import Speech
import AVFoundation

/// Manages continuous speech recognition and produces timestamped transcript segments.
final class SpeechRecognitionService: NSObject {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var _isRecording = false
    var isRecording: Bool { _isRecording }

    /// Fires with the full cumulative transcript text (for live UI display).
    var onTranscript: ((String, TimeInterval) -> Void)?

    /// Fires each time a time-windowed transcript segment is completed.
    var onSegmentsFinalized: (([TranscriptSegment]) -> Void)?

    /// The size of each time window in seconds.
    var segmentWindowSize: TimeInterval = 5.0

    private var recordingStartTime: Date?
    private var lastTranscript: String = ""

    /// Text accumulated from prior recognition sessions (Apple restarts ~every 60s).
    private var priorSessionsText: String = ""

    // Timer-based segmentation state
    private var segmentTimer: Timer?
    private var lastSnapshotText: String = ""
    private var currentSegmentStart: TimeInterval = 0

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func startRecording(startTime: Date) async throws {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw SpeechError.notAvailable
        }

        recognitionTask?.cancel()
        recognitionTask = nil

        recordingStartTime = startTime
        lastTranscript = ""
        priorSessionsText = ""
        lastSnapshotText = ""
        currentSegmentStart = 0

        try await Task.detached(priority: .userInitiated) { [audioEngine] in
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            // inputNode access lazily creates the audio graph – expensive
            let inputNode = audioEngine.inputNode
            inputNode.removeTap(onBus: 0)
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak audioEngine] buffer, _ in
                _ = audioEngine
            }

            audioEngine.prepare()
        }.value

        setupRecognitionRequest()
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        startRecognitionTask(restartOnEnd: true)

        try audioEngine.start()
        _isRecording = true
        startSegmentTimer()
    }

    func stopRecording() {
        _isRecording = false
        stopSegmentTimer()
        snapshotSegment()
        
        let engine = audioEngine
        let task = recognitionTask
        let request = recognitionRequest
        
        recognitionRequest = nil
        recognitionTask = nil
        
        Task.detached(priority: .background) {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            request?.endAudio()
            task?.cancel()
        }
    }

    func pauseRecording() {
        stopSegmentTimer()
        snapshotSegment()
        
        let engine = audioEngine
        let request = recognitionRequest
        
        Task.detached(priority: .background) {
            engine.pause()
            request?.endAudio()
        }
    }

    func resumeRecording() throws {
        guard let speechRecognizer, speechRecognizer.isAvailable else { return }

        setupRecognitionRequest()
        installAudioTap()
        startRecognitionTask(restartOnEnd: true)

        try audioEngine.start()
        startSegmentTimer()
    }

    private func restartRecognition() {
        // Accumulate the session text so the next session's cumulative display is correct.
        if !lastTranscript.isEmpty {
            priorSessionsText += (priorSessionsText.isEmpty ? "" : " ") + lastTranscript
        }
        lastTranscript = ""

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        guard let speechRecognizer, speechRecognizer.isAvailable else { return }

        setupRecognitionRequest()
        installAudioTap()
        startRecognitionTask(restartOnEnd: true)

        do {
            try audioEngine.start()
        } catch {
            _isRecording = false
        }
    }

    // MARK: - Shared Helpers

    private func setupRecognitionRequest() {
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true
        recognitionRequest?.addsPunctuation = true
    }

    private func installAudioTap() {
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
    }

    private func startRecognitionTask(restartOnEnd: Bool) {
        guard let speechRecognizer, let recognitionRequest else { return }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let sessionText = result.bestTranscription.formattedString
                if sessionText != self.lastTranscript {
                    let timestamp = Date().timeIntervalSince(self.recordingStartTime ?? Date())
                    self.lastTranscript = sessionText

                    let fullText = self.priorSessionsText.isEmpty
                        ? sessionText
                        : self.priorSessionsText + " " + sessionText
                    self.onTranscript?(fullText, timestamp)
                }
            }

            if restartOnEnd, error != nil || (result?.isFinal ?? false) {
                if self._isRecording {
                    self.restartRecognition()
                }
            }
        }
    }

    enum SpeechError: Error, LocalizedError {
        case notAvailable
        case requestFailed
        case notAuthorized

        var errorDescription: String? {
            switch self {
            case .notAvailable: return "Spracherkennung nicht verfügbar"
            case .requestFailed: return "Spracherkennung konnte nicht gestartet werden"
            case .notAuthorized: return "Spracherkennung nicht autorisiert"
            }
        }
    }

    // MARK: - Timer-based Segmentation

    private func startSegmentTimer() {
        segmentTimer = Timer.scheduledTimer(withTimeInterval: segmentWindowSize, repeats: true) { [weak self] _ in
            self?.snapshotSegment()
        }
    }

    private func stopSegmentTimer() {
        segmentTimer?.invalidate()
        segmentTimer = nil
    }

    /// Captures the delta between the current full text and the last snapshot,
    /// emitting a `TranscriptSegment` for the current time window.
    private func snapshotSegment() {
        let fullText = buildFullText()
        let delta = extractDelta(current: fullText, previous: lastSnapshotText)
        let now = Date().timeIntervalSince(recordingStartTime ?? Date())

        if !delta.isEmpty {
            let segment = TranscriptSegment(
                startTime: currentSegmentStart,
                endTime: now,
                text: delta
            )
            onSegmentsFinalized?([segment])
        }

        lastSnapshotText = fullText
        currentSegmentStart = now
    }

    private func buildFullText() -> String {
        if priorSessionsText.isEmpty { return lastTranscript }
        if lastTranscript.isEmpty { return priorSessionsText }
        return priorSessionsText + " " + lastTranscript
    }

    private func extractDelta(current: String, previous: String) -> String {
        guard current.count > previous.count else { return "" }
        let commonLen = current.commonPrefix(with: previous).count
        return String(current.dropFirst(commonLen)).trimmingCharacters(in: .whitespaces)
    }
}
