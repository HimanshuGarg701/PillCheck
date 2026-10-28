import AVFoundation
import Speech
import Foundation

@MainActor
final class SpeechService: ObservableObject {
    @Published var listening = false
    @Published var preparing = false
    @Published var transcript = ""
    @Published var message: String?
    private let speaker = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timeout: Task<Void, Never>?
    private var tapInstalled = false
    private var sessionID: UUID?

    func speak(_ text: String, language: String) {
        stopListening()
        speaker.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = 0.43
        speaker.speak(utterance)
    }
    func stop() { speaker.stopSpeaking(at: .immediate); stopListening() }
    func listen(language: String, onCommand: @escaping (String) -> Void) async {
        stop()
        let id = UUID()
        sessionID = id
        preparing = true
        defer { if sessionID == id { preparing = false } }
        message = nil
        transcript = ""
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard sessionID == id, !Task.isCancelled else { return }
        guard speech == .authorized else { message = "Allow speech access in Settings, or use the large buttons."; return }
        let mic = await AVAudioApplication.requestRecordPermission()
        guard sessionID == id, !Task.isCancelled else { return }
        guard mic else { message = "Allow microphone access in Settings, or use the large buttons."; return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            message = "On-device speech is unavailable for this language. Use the buttons; your audio will not be sent to a speech server."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            self.request = request
            let node = engine.inputNode
            let format = node.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else { throw PillCheckError("The microphone is unavailable. Use the Done button.") }
            node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            tapInstalled = true
            engine.prepare()
            try engine.start()
            listening = true
            transcript = ""
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.sessionID == id, self.listening else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        if result.isFinal {
                            let command = VoiceConfirmationCommand.parse(self.transcript, isFinal: result.isFinal)
                            self.stopListening()
                            if let command { onCommand(command.rawValue) }
                            else { self.message = "No confirmation recorded. Say only Done or Next, or use a button." }
                        }
                    } else if let error { self.stopListening(); self.message = error.localizedDescription }
                }
            }
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled, let self, self.sessionID == id else { return }
                self.engine.stop()
                self.request?.endAudio()
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled, self.sessionID == id, self.listening else { return }
                self.stopListening()
                self.message = "No confirmation recorded. Try again, or use the large buttons."
            }
        } catch { stopListening(); message = error.localizedDescription }
    }
    private func stopListening() {
        // Invalidate first: cancellation itself can deliver an old final result.
        sessionID = nil
        preparing = false
        timeout?.cancel(); timeout = nil
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio(); request = nil
        task?.cancel(); task = nil
        listening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
