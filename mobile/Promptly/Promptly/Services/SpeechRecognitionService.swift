import Foundation
import Speech
import AVFoundation

class SpeechRecognitionService {
    private var audioEngine: AVAudioEngine
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var isAuthorized = false
    private var silenceTimer: Timer?
    private var lastTranscriptionTime: Date?
    private var onStopRecording: (() -> Void)?
    
    init() {
        audioEngine = AVAudioEngine()
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }
    
    func requestAuthorization() async -> Bool {
        // First check speech recognition authorization
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        
        guard speechStatus == .authorized else {
            return false
        }
        
        // Then check microphone authorization
        let micStatus = AVAudioSession.sharedInstance().recordPermission
        
        switch micStatus {
        case .undetermined:
            let granted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            }
            isAuthorized = granted
            return granted
            
        case .granted:
            isAuthorized = true
            return true
            
        case .denied:
            isAuthorized = false
            return false
            
        @unknown default:
            isAuthorized = false
            return false
        }
    }
    
    private func cleanupRecordingSession() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        lastTranscriptionTime = nil
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        // Deactivate the audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Handle error silently
        }
        
        recognitionRequest = nil
        recognitionTask = nil
    }
    
    func startRecording(onTranscription: @escaping (String) -> Void, onStop: @escaping () -> Void) throws {
        self.onStopRecording = onStop
        
        guard isAuthorized else {
            throw SpeechRecognitionError.notAuthorized
        }
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw SpeechRecognitionError.recognitionNotAvailable
        }
        
        // Clean up any existing session without triggering callback
        cleanupRecordingSession()
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw error
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw SpeechRecognitionError.recognitionNotAvailable
        }
        
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .dictation
        
        // Start the silence timer
        lastTranscriptionTime = Date()
        startSilenceTimer()
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let result = result, !result.bestTranscription.formattedString.isEmpty {
                    self.lastTranscriptionTime = Date() // Reset the timer when we get new speech
                    onTranscription(result.bestTranscription.formattedString)
                }
                if let error = error {
                    // Ignore cancellation and no-speech errors
                    if error.localizedDescription != "Recognition request was canceled" &&
                       error.localizedDescription != "No speech detected" {
                        self.stopRecording()
                    }
                }
            }
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            stopRecording()
            throw error
        }
    }
    
    private func startSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self,
                  let lastTime = self.lastTranscriptionTime else { return }
            
            let timeSinceLastTranscription = Date().timeIntervalSince(lastTime)
            if timeSinceLastTranscription >= 10.0 {
                self.stopRecording()
            }
        }
    }
    
    func stopRecording() {
        // Call the callback before stopping
        let callback = onStopRecording
        onStopRecording = nil
        callback?()
        
        cleanupRecordingSession()
    }
}

enum SpeechRecognitionError: LocalizedError {
    case recognitionNotAvailable
    case notAuthorized
    case microphoneAccessDenied
    
    var errorDescription: String? {
        switch self {
        case .recognitionNotAvailable:
            return "Speech recognition is not available on this device"
        case .notAuthorized:
            return "Speech recognition is not authorized. Please check your privacy settings"
        case .microphoneAccessDenied:
            return "Microphone access is denied. Please check your privacy settings"
        }
    }
} 
