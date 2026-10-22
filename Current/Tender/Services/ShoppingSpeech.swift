import SwiftUI
import Speech
import AVFoundation

@MainActor @Observable
final class ShoppingSpeech {
    var text = ""
    var message: String?
    var recording = false
    private var engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var hasTap = false
    private var generation = UUID()
    private var starting = false
    func start(appendingTo existingText: String = "") async {
        guard !recording, !starting else { return }
        starting = true; defer { starting = false }
        let permissionGeneration = generation
        let permission = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard permission == .authorized, await AVCaptureDevice.requestAccess(for: .audio) else {
            message = "Enable microphone and speech access in iPhone Settings, or type your plan."; return
        }
        guard generation == permissionGeneration else { return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            message = "On-device speech is unavailable. Type your plan or use keyboard dictation."; return
        }
        stop(); text = existingText.trimmingCharacters(in: .whitespacesAndNewlines); message = nil
        begin(recognizer)
    }
    private func begin(_ recognizer: SFSpeechRecognizer) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
            self.request = request
            let node = engine.inputNode
            let format = node.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw CocoaError(.featureUnsupported) }
            node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            hasTap = true; engine.prepare(); try engine.start(); recording = true
            let generation = self.generation
            // New recognition tasks and post-pause utterances append to the
            // committed transcript. Revisions within an utterance replace only it.
            var committed = text
            var partial = ""
            var firstTimestamp: TimeInterval?
            var previousEnd: TimeInterval = 0
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.generation == generation else { return }
                    if let result {
                        let transcription = result.bestTranscription
                        if let first = transcription.segments.first?.timestamp {
                            if let previous = firstTimestamp, first > previous + 0.1, first >= previousEnd - 0.05, !partial.isEmpty {
                                committed = [committed, partial].filter { !$0.isEmpty }.joined(separator: " ")
                            }
                            firstTimestamp = first
                        }
                        if let last = transcription.segments.last { previousEnd = last.timestamp + last.duration }
                        partial = transcription.formattedString
                        self.text = [committed, partial].filter { !$0.isEmpty }.joined(separator: " ")
                    }
                    if result?.isFinal == true && error == nil {
                        // Speech may finalize on a pause. Keep listening until the
                        // user taps stop; carry the completed words into the next task.
                        self.endCapture()
                        self.generation = UUID()
                        self.begin(recognizer)
                    } else if error != nil {
                        self.stop()
                        self.message = "Dictation paused. Your words are kept; tap the microphone to continue."
                    }
                }
            }
        } catch { stop(); message = "Couldn’t start the microphone. Your text is kept; try typing or dictate again." }
    }
    private func endCapture() {
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        request?.endAudio(); task?.cancel(); task = nil; request = nil
    }
    func stop() {
        generation = UUID()
        endCapture(); recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
