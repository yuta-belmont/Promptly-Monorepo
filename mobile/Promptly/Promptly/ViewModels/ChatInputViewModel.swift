import Foundation
import SwiftUI

@MainActor
class ChatInputViewModel: ObservableObject {
    @Published var userInput: String = ""
    @Published var isRecording = false
    @Published var isSpeechSetup = false
    @Published var errorMessage: String?
    
    private let speechService: SpeechRecognitionService
    private var isStoppingRecording = false
    
    init(speechService: SpeechRecognitionService = SpeechRecognitionService()) {
        self.speechService = speechService
    }
    
    func setupSpeechRecognition() {
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
    
    func toggleRecording() {
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
            // Only clear existing input if we're starting a new recording
            _ = userInput
            userInput = ""
            try speechService.startRecording { [weak self] transcription in
                self?.userInput = transcription
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
        
        // Store the current transcription before stopping
        let finalTranscription = userInput
        
        // Update UI state immediately to provide feedback
        isRecording = false
        
        // Add a 1-second delay before actually stopping the recording
        // This gives the speech recognition system time to process the final parts of speech
        Task {
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                
                // Stop the service after the delay
                self.speechService.stopRecording()
                
                // Ensure we keep the final transcription, but check if it was updated during the delay
                if !self.userInput.isEmpty {
                    // Keep current transcription
                } else if !finalTranscription.isEmpty {
                    self.userInput = finalTranscription
                }
            } catch {
                // Stop the service anyway in case of error
                self.speechService.stopRecording()
            }
            
            self.isStoppingRecording = false
        }
    }
    
    func sendMessage() {
        userInput = ""
    }
} 
