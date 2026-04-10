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

    var onTranscript: ((String, TimeInterval) -> Void)?

    private var recordingStartTime: Date?
    private var lastTranscript: String = ""

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

        // Move all heavy audio setup off the main thread
        try await Task.detached(priority: .userInitiated) { [audioEngine] in
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            // inputNode access lazily creates the audio graph – expensive
            let inputNode = audioEngine.inputNode
            inputNode.removeTap(onBus: 0)
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak audioEngine] buffer, _ in
                _ = audioEngine // prevent retain cycle warning
            }

            audioEngine.prepare()
        }.value

        setupRecognitionRequest()
        // Re-install tap with the actual request now that it exists
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        startRecognitionTask(restartOnEnd: true)

        try audioEngine.start()
        _isRecording = true
    }

    func stopRecording() {
        _isRecording = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    func pauseRecording() {
        audioEngine.pause()
        recognitionRequest?.endAudio()
    }

    func resumeRecording() throws {
        guard let speechRecognizer, speechRecognizer.isAvailable else { return }

        setupRecognitionRequest()
        installAudioTap()
        startRecognitionTask(restartOnEnd: true)

        try audioEngine.start()
    }

    private func restartRecognition() {
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
                let text = result.bestTranscription.formattedString
                if text != self.lastTranscript {
                    let timestamp = Date().timeIntervalSince(self.recordingStartTime ?? Date())
                    self.lastTranscript = text
                    self.onTranscript?(text, timestamp)
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
}
