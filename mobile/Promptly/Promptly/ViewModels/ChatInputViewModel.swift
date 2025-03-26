import Foundation
import SwiftUI

@MainActor
class ChatInputViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var isSpeechSetup = false
    @Published var errorMessage: String?
    
    private let speechService: SpeechRecognitionService
    private var isStoppingRecording = false
    private var directUpdateHandler: ((String) -> Void)?
    
    init(speechService: SpeechRecognitionService = SpeechRecognitionService()) {
        self.speechService = speechService
    }
    
    func setupSpeechRecognition(directUpdateHandler: ((String) -> Void)? = nil) {
        self.directUpdateHandler = directUpdateHandler
        
        Task {
            do {
                let wasAuthorized = await speechService.requestAuthorization()
                
                if wasAuthorized {
                    isSpeechSetup = true
                } else {
                    isSpeechSetup = false
                    errorMessage = "Please enable both microphone and speech recognition in Settings to use voice input"
                }
            } catch {
                isSpeechSetup = false
                errorMessage = error.localizedDescription
            }
        }
    }
    
    func toggleRecording(directUpdateHandler: ((String) -> Void)? = nil) {
        if directUpdateHandler != nil {
            self.directUpdateHandler = directUpdateHandler
        }
        
        if !isSpeechSetup {
            errorMessage = "Please enable both microphone and speech recognition in Settings"
            return
        }
        
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        do {
            // Clear existing input by sending empty string
            directUpdateHandler?("")
            
            try speechService.startRecording { [weak self] transcription in
                // Update directly with the transcription
                self?.directUpdateHandler?(transcription)
            } onStop: { [weak self] in
                guard let self = self else { return }
                // When automatically stopped, just update the state
                DispatchQueue.main.async {
                    self.isRecording = false
                }
            }
            isRecording = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            isRecording = false
        }
    }
    
    private func stopRecording() {
        // Prevent recursive calls
        guard !isStoppingRecording else { return }
        isStoppingRecording = true
        
        // Capture the current handler for use in the task
        let currentHandler = directUpdateHandler
        
        // Update UI state immediately to provide feedback
        isRecording = false
        
        // Add a 1-second delay before actually stopping the recording
        // This gives the speech recognition system time to process the final parts of speech
        Task {
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                
                // Stop the service after the delay
                self.speechService.stopRecording()
                
                // The current transcription will be maintained by the parent binding
                // We don't need to do anything additional here
            } catch {
                // Stop the service anyway in case of error
                self.speechService.stopRecording()
            }
            
            self.isStoppingRecording = false
        }
    }
    
    func sendMessage() {
        // Implementation of sendMessage method
    }
} 
