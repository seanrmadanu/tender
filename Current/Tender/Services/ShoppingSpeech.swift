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
    func start() async {
        guard !recording else { return }
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
        do {
            stop(); text = ""; message = nil
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
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.generation == generation else { return }
                    if let result { self.text = result.bestTranscription.formattedString }
                    if result?.isFinal == true || error != nil { self.stop() }
                    if error != nil && self.text.isEmpty { self.message = "Speech wasn’t recognized. Try again or type your plan." }
                }
            }
        } catch { stop(); message = "Couldn’t start the microphone. Try typing your plan." }
    }
    func stop() {
        generation = UUID()
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        request?.endAudio(); task?.cancel(); task = nil; request = nil; recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
